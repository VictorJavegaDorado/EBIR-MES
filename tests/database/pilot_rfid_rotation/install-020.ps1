[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigurationPath,
    [string]$SqlServer = 'SQL.EBIR.LOCAL\NAVISION2017',
    [string]$Database = 'EBIR_MES_TEST',
    [switch]$ValidateOnly,
    [string]$VerifiedBackupPath,
    [switch]$ConfirmAuthorizedExecution
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ConfirmAuthorizedExecution) { throw 'Falta -ConfirmAuthorizedExecution.' }
if ($SqlServer -cne 'SQL.EBIR.LOCAL\NAVISION2017' -or $Database -cne 'EBIR_MES_TEST') {
    throw 'El paquete 020 solo admite SQL.EBIR.LOCAL\NAVISION2017/EBIR_MES_TEST.'
}

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$configurationFile = (Resolve-Path -LiteralPath $ConfigurationPath).Path
if ($configurationFile.StartsWith(
        $repositoryRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'La configuracion RFID debe permanecer fuera del repositorio.'
}
if (-not $ValidateOnly -and [string]::IsNullOrWhiteSpace($VerifiedBackupPath)) {
    throw 'La instalacion requiere identificar un backup COPY_ONLY verificado.'
}
if (-not $ValidateOnly -and
    (-not [IO.Path]::IsPathRooted($VerifiedBackupPath) -or
     [IO.Path]::GetExtension($VerifiedBackupPath) -cne '.bak')) {
    throw 'La evidencia de backup debe ser una ruta absoluta con extension .bak.'
}

$packagePath = Join-Path $repositoryRoot 'database\020A_rotacion_credenciales_rfid_piloto.sql'
$packageSql = Get-Content -LiteralPath $packagePath -Raw
$configuration = Get-Content -LiteralPath $configurationFile -Raw | ConvertFrom-Json
$credentials = @($configuration.credentials)

if ([string]$configuration.purpose -cne 'PILOT_020_RFID_ROTATION' -or
    $configuration.originalCredentialsStored -ne $false) {
    throw 'La configuracion protegida no declara el contrato del paquete 020.'
}
if ($credentials.Count -ne 2 -or
    @($credentials.navCode | Sort-Object -Unique).Count -ne 2 -or
    @($credentials.navCode | Where-Object { $_ -in @('325','884') }).Count -ne 2) {
    throw 'La configuracion requiere exactamente los dos empleados TEST autorizados.'
}
if (@($credentials.roleCode | Where-Object { $_ -ceq 'OPERARIO' }).Count -ne 2) {
    throw 'Las dos rotaciones deben conservar rol OPERARIO.'
}
foreach ($credential in $credentials) {
    if ([string]$credential.rfidLookupHex -notmatch '\A[0-9A-Fa-f]{64}\z') {
        throw 'Cada huella RFID debe contener exactamente 32 bytes hexadecimales.'
    }
}
if (@($credentials.rfidLookupHex | Sort-Object -Unique).Count -ne 2) {
    throw 'Las dos huellas RFID deben ser distintas.'
}

function Convert-HexToBytes {
    param([Parameter(Mandatory = $true)][string]$Hex)
    $bytes = New-Object byte[] 32
    for ($index = 0; $index -lt $bytes.Length; $index++) {
        $bytes[$index] = [Convert]::ToByte($Hex.Substring($index * 2, 2), 16)
    }
    Write-Output -NoEnumerate $bytes
}

$connectionString = [Data.SqlClient.SqlConnectionStringBuilder]::new()
$connectionString['Data Source'] = $SqlServer
$connectionString['Initial Catalog'] = $Database
$connectionString['Integrated Security'] = $true
$connectionString['Encrypt'] = $true
$connectionString['TrustServerCertificate'] = $true
$connectionString['Application Name'] = 'EBIR-MES-Package-020'

$connection = [Data.SqlClient.SqlConnection]::new($connectionString.ConnectionString)
$transaction = $null
try {
    $connection.Open()
    if ($connection.Database -cne 'EBIR_MES_TEST') { throw 'La conexion no apunta a EBIR_MES_TEST.' }
    $transaction = $connection.BeginTransaction([Data.IsolationLevel]::Serializable)

    $setup = $connection.CreateCommand()
    $setup.Transaction = $transaction
    $setup.CommandText = @'
CREATE TABLE #pilot_rfid_rotations
(
    codigo_nav nvarchar(30) NOT NULL,
    rol_codigo nvarchar(30) NOT NULL,
    rfid_busqueda varbinary(32) NOT NULL
);
'@
    [void]$setup.ExecuteNonQuery()
    $setup.Dispose()

    foreach ($credential in $credentials) {
        $insert = $connection.CreateCommand()
        $insert.Transaction = $transaction
        $insert.CommandText = @'
INSERT #pilot_rfid_rotations (codigo_nav, rol_codigo, rfid_busqueda)
VALUES (@codigo_nav, @rol_codigo, @rfid_busqueda);
'@
        [void]$insert.Parameters.Add('@codigo_nav',[Data.SqlDbType]::NVarChar,30)
        [void]$insert.Parameters.Add('@rol_codigo',[Data.SqlDbType]::NVarChar,30)
        [void]$insert.Parameters.Add('@rfid_busqueda',[Data.SqlDbType]::VarBinary,32)
        $insert.Parameters['@codigo_nav'].Value = [string]$credential.navCode
        $insert.Parameters['@rol_codigo'].Value = [string]$credential.roleCode
        [byte[]]$fingerprint = Convert-HexToBytes ([string]$credential.rfidLookupHex)
        $insert.Parameters['@rfid_busqueda'].Value = $fingerprint
        [void]$insert.ExecuteNonQuery()
        $insert.Dispose()
        [Array]::Clear($fingerprint,0,$fingerprint.Length)
    }

    $package = $connection.CreateCommand()
    $package.Transaction = $transaction
    $package.CommandTimeout = 120
    $package.CommandText = $packageSql
    $reader = $package.ExecuteReader()
    $result = $null
    do {
        if ($reader.FieldCount -gt 0 -and $reader.Read()) {
            $result = [pscustomobject]@{
                EmployeeCount = [int]$reader['empleados_configurados']
                RevokedCredentialCount = [int]$reader['credenciales_revocadas']
                ActiveCredentialCount = [int]$reader['credenciales_configuradas']
                CorrelationId = [guid]$reader['correlacion_id']
            }
        }
    } while ($reader.NextResult())
    $reader.Close()
    $reader.Dispose()
    $package.Dispose()

    if ($null -eq $result) { throw 'El paquete 020 no devolvio evidencia.' }
    if ($result.EmployeeCount -ne 2 -or
        $result.RevokedCredentialCount -ne 2 -or
        $result.ActiveCredentialCount -ne 2) {
        throw 'La evidencia devuelta por el paquete 020 no coincide con el contrato.'
    }

    if ($ValidateOnly) {
        $transaction.Rollback()
        $mode = 'VALIDATED_AND_ROLLED_BACK'
    }
    else {
        $transaction.Commit()
        $mode = 'INSTALLED'
    }
    $transaction.Dispose()
    $transaction = $null

    [pscustomobject]@{
        Mode = $mode
        Database = $Database
        EmployeeCount = $result.EmployeeCount
        RevokedCredentialCount = $result.RevokedCredentialCount
        ActiveCredentialCount = $result.ActiveCredentialCount
        CorrelationId = $result.CorrelationId
        VerifiedBackupPath = if ($ValidateOnly) { $null } else { $VerifiedBackupPath }
    }
}
finally {
    if ($null -ne $transaction) {
        try { $transaction.Rollback() } catch { }
        $transaction.Dispose()
    }
    if ($connection.State -ne [Data.ConnectionState]::Closed) { $connection.Close() }
    $connection.Dispose()
}
