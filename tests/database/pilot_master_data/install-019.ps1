[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $ConfigurationPath,

    [string] $SqlServer = 'SQL.EBIR.LOCAL\NAVISION2017',

    [string] $Database = 'EBIR_MES_TEST',

    [switch] $ValidateOnly,

    [string] $VerifiedBackupPath,

    [switch] $ConfirmAuthorizedExecution
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ConfirmAuthorizedExecution) {
    throw 'Falta -ConfirmAuthorizedExecution.'
}
if ($SqlServer -cne 'SQL.EBIR.LOCAL\NAVISION2017' -or
    $Database -cne 'EBIR_MES_TEST') {
    throw 'El paquete 019 solo admite SQL.EBIR.LOCAL\NAVISION2017/EBIR_MES_TEST.'
}

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$configurationFile = (Resolve-Path -LiteralPath $ConfigurationPath).Path
if ($configurationFile.StartsWith(
        $repositoryRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'La configuracion fisica y personal debe permanecer fuera del repositorio.'
}
if (-not $ValidateOnly -and [string]::IsNullOrWhiteSpace($VerifiedBackupPath)) {
    throw 'La instalacion requiere identificar un backup COPY_ONLY verificado.'
}
if (-not $ValidateOnly -and
    (-not [IO.Path]::IsPathRooted($VerifiedBackupPath) -or
     [IO.Path]::GetExtension($VerifiedBackupPath) -cne '.bak')) {
    throw 'La evidencia de backup debe ser una ruta absoluta con extension .bak.'
}

$packagePath = Join-Path $repositoryRoot 'database\019A_maestros_piloto_test.sql'
$packageSql = Get-Content -LiteralPath $packagePath -Raw
$configuration = Get-Content -LiteralPath $configurationFile -Raw |
    ConvertFrom-Json

if (@($configuration.employees).Count -ne 3) {
    throw 'La configuracion debe contener exactamente tres empleados TEST.'
}

$roles = @($configuration.employees | ForEach-Object { [string] $_.roleCode })
if (@($roles | Where-Object { $_ -ceq 'OPERARIO' }).Count -ne 2 -or
    @($roles | Where-Object { $_ -ceq 'SUPERVISOR' }).Count -ne 1) {
    throw 'La configuracion requiere dos OPERARIO y un SUPERVISOR.'
}

foreach ($employee in $configuration.employees) {
    if ([string] $employee.rfidLookupHex -notmatch '\A[0-9A-Fa-f]{64}\z') {
        throw 'Cada rfidLookupHex debe ser una huella hexadecimal de 32 bytes.'
    }
}

function Add-DbParameter {
    param(
        [Parameter(Mandatory = $true)] [Data.SqlClient.SqlCommand] $Command,
        [Parameter(Mandatory = $true)] [string] $Name,
        [Parameter(Mandatory = $true)] [Data.SqlDbType] $Type,
        [int] $Size = 0,
        [AllowNull()] $Value
    )

    $parameter = if ($Size -gt 0) {
        $Command.Parameters.Add($Name, $Type, $Size)
    }
    else {
        $Command.Parameters.Add($Name, $Type)
    }
    if ($null -eq $Value -or
        ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value))) {
        $parameter.Value = [DBNull]::Value
    }
    elseif ($Type -eq [Data.SqlDbType]::VarBinary) {
        $parameter.Value = [byte[]] $Value
    }
    else {
        $parameter.Value = $Value
    }
}

function Convert-HexToBytes {
    param([Parameter(Mandatory = $true)] [string] $Hex)

    if ($Hex -notmatch '\A[0-9A-Fa-f]{64}\z') {
        throw 'La huella RFID no es hexadecimal de 32 bytes.'
    }
    $bytes = New-Object byte[] 32
    for ($index = 0; $index -lt $bytes.Length; $index++) {
        $bytes[$index] = [Convert]::ToByte($Hex.Substring($index * 2, 2), 16)
    }
    Write-Output -NoEnumerate $bytes
}

function New-TransactionalCommand {
    param(
        [Parameter(Mandatory = $true)] [Data.SqlClient.SqlConnection] $Connection,
        [Parameter(Mandatory = $true)] [Data.SqlClient.SqlTransaction] $Transaction,
        [Parameter(Mandatory = $true)] [string] $Text
    )

    $command = $Connection.CreateCommand()
    $command.Transaction = $Transaction
    $command.CommandTimeout = 120
    $command.CommandText = $Text
    $command
}

$connectionString = [Data.SqlClient.SqlConnectionStringBuilder]::new()
$connectionString['Data Source'] = $SqlServer
$connectionString['Initial Catalog'] = $Database
$connectionString['Integrated Security'] = $true
$connectionString['Encrypt'] = $true
$connectionString['TrustServerCertificate'] = $true
$connectionString['Application Name'] = 'EBIR-MES-Package-019'

$connection = [Data.SqlClient.SqlConnection]::new($connectionString.ConnectionString)
$transaction = $null
try {
    $connection.Open()
    if ($connection.Database -cne 'EBIR_MES_TEST') {
        throw 'La conexion no apunta a EBIR_MES_TEST.'
    }

    $transaction = $connection.BeginTransaction([Data.IsolationLevel]::Serializable)

    $setup = New-TransactionalCommand -Connection $connection -Transaction $transaction -Text @'
CREATE TABLE #pilot_linea
(
    centro_codigo nvarchar(30) NOT NULL,
    codigo nvarchar(20) NOT NULL,
    nombre nvarchar(100) NOT NULL,
    descripcion nvarchar(250) NULL
);
CREATE TABLE #pilot_impresora
(
    codigo nvarchar(30) NOT NULL,
    nombre nvarchar(100) NOT NULL,
    modelo nvarchar(100) NOT NULL,
    nombre_red nvarchar(255) NULL,
    direccion_ip varchar(45) NULL,
    protocolo nvarchar(30) NOT NULL,
    resolucion_dpi smallint NOT NULL
);
CREATE TABLE #pilot_dispositivo
(
    codigo nvarchar(30) NOT NULL,
    nombre nvarchar(100) NOT NULL,
    tipo nvarchar(30) NOT NULL,
    nombre_equipo nvarchar(128) NULL,
    direccion_red nvarchar(255) NULL
);
CREATE TABLE #pilot_empleados
(
    codigo_nav nvarchar(30) NOT NULL,
    nombre_completo nvarchar(200) NOT NULL,
    cargo nvarchar(100) NULL,
    alias nvarchar(100) NULL,
    rol_interno_nav nvarchar(100) NULL,
    proceso_codigo nvarchar(50) NULL,
    tipo_mano_obra nvarchar(20) NULL,
    grupo_turno nvarchar(30) NULL,
    rol_codigo nvarchar(30) NOT NULL,
    rfid_busqueda varbinary(32) NOT NULL,
    ultimos_caracteres nvarchar(8) NULL,
    sincronizado_nav_utc datetime2(3) NOT NULL
);
'@
    [void] $setup.ExecuteNonQuery()
    $setup.Dispose()

    $lineCommand = New-TransactionalCommand -Connection $connection -Transaction $transaction -Text @'
INSERT #pilot_linea (centro_codigo, codigo, nombre, descripcion)
VALUES (@centro, @codigo, @nombre, @descripcion);
'@
    Add-DbParameter $lineCommand '@centro' NVarChar 30 ([string] $configuration.centerCode)
    Add-DbParameter $lineCommand '@codigo' NVarChar 20 ([string] $configuration.line.code)
    Add-DbParameter $lineCommand '@nombre' NVarChar 100 ([string] $configuration.line.name)
    Add-DbParameter $lineCommand '@descripcion' NVarChar 250 $configuration.line.description
    [void] $lineCommand.ExecuteNonQuery()
    $lineCommand.Dispose()

    $printerCommand = New-TransactionalCommand -Connection $connection -Transaction $transaction -Text @'
INSERT #pilot_impresora
(codigo, nombre, modelo, nombre_red, direccion_ip, protocolo, resolucion_dpi)
VALUES (@codigo, @nombre, @modelo, @nombre_red, @direccion_ip, @protocolo, @dpi);
'@
    Add-DbParameter $printerCommand '@codigo' NVarChar 30 ([string] $configuration.printer.code)
    Add-DbParameter $printerCommand '@nombre' NVarChar 100 ([string] $configuration.printer.name)
    Add-DbParameter $printerCommand '@modelo' NVarChar 100 ([string] $configuration.printer.model)
    Add-DbParameter $printerCommand '@nombre_red' NVarChar 255 $configuration.printer.networkName
    Add-DbParameter $printerCommand '@direccion_ip' VarChar 45 $configuration.printer.ipAddress
    Add-DbParameter $printerCommand '@protocolo' NVarChar 30 ([string] $configuration.printer.protocol)
    Add-DbParameter $printerCommand '@dpi' SmallInt 0 ([int] $configuration.printer.dpi)
    [void] $printerCommand.ExecuteNonQuery()
    $printerCommand.Dispose()

    $deviceCommand = New-TransactionalCommand -Connection $connection -Transaction $transaction -Text @'
INSERT #pilot_dispositivo
(codigo, nombre, tipo, nombre_equipo, direccion_red)
VALUES (@codigo, @nombre, @tipo, @nombre_equipo, @direccion_red);
'@
    Add-DbParameter $deviceCommand '@codigo' NVarChar 30 ([string] $configuration.device.code)
    Add-DbParameter $deviceCommand '@nombre' NVarChar 100 ([string] $configuration.device.name)
    Add-DbParameter $deviceCommand '@tipo' NVarChar 30 ([string] $configuration.device.type)
    Add-DbParameter $deviceCommand '@nombre_equipo' NVarChar 128 $configuration.device.computerName
    Add-DbParameter $deviceCommand '@direccion_red' NVarChar 255 $configuration.device.networkAddress
    [void] $deviceCommand.ExecuteNonQuery()
    $deviceCommand.Dispose()

    foreach ($employee in $configuration.employees) {
        $employeeCommand = New-TransactionalCommand -Connection $connection -Transaction $transaction -Text @'
INSERT #pilot_empleados
(
    codigo_nav, nombre_completo, cargo, alias, rol_interno_nav,
    proceso_codigo, tipo_mano_obra, grupo_turno, rol_codigo,
    rfid_busqueda, ultimos_caracteres, sincronizado_nav_utc
)
VALUES
(
    @codigo_nav, @nombre_completo, @cargo, @alias, @rol_interno_nav,
    @proceso_codigo, @tipo_mano_obra, @grupo_turno, @rol_codigo,
    @rfid_busqueda, @ultimos_caracteres, @sincronizado_nav_utc
);
'@
        Add-DbParameter $employeeCommand '@codigo_nav' NVarChar 30 ([string] $employee.navCode)
        Add-DbParameter $employeeCommand '@nombre_completo' NVarChar 200 ([string] $employee.fullName)
        Add-DbParameter $employeeCommand '@cargo' NVarChar 100 $employee.jobTitle
        Add-DbParameter $employeeCommand '@alias' NVarChar 100 $employee.alias
        Add-DbParameter $employeeCommand '@rol_interno_nav' NVarChar 100 $employee.navRole
        Add-DbParameter $employeeCommand '@proceso_codigo' NVarChar 50 $employee.processCode
        Add-DbParameter $employeeCommand '@tipo_mano_obra' NVarChar 20 $employee.laborType
        Add-DbParameter $employeeCommand '@grupo_turno' NVarChar 30 $employee.shiftGroup
        Add-DbParameter $employeeCommand '@rol_codigo' NVarChar 30 ([string] $employee.roleCode)
        [byte[]] $rfidLookup = Convert-HexToBytes ([string] $employee.rfidLookupHex)
        Add-DbParameter $employeeCommand '@rfid_busqueda' VarBinary 32 $rfidLookup
        Add-DbParameter $employeeCommand '@ultimos_caracteres' NVarChar 8 $employee.lastCharacters
        $synchronizedUtc = [DateTimeOffset]::Parse(
            [string] $employee.synchronizedNavUtc,
            [Globalization.CultureInfo]::InvariantCulture).UtcDateTime
        Add-DbParameter $employeeCommand '@sincronizado_nav_utc' DateTime2 0 $synchronizedUtc
        [void] $employeeCommand.ExecuteNonQuery()
        $employeeCommand.Dispose()
    }

    $packageCommand = New-TransactionalCommand -Connection $connection -Transaction $transaction -Text $packageSql
    $reader = $packageCommand.ExecuteReader()
    $result = $null
    do {
        if ($reader.FieldCount -gt 0 -and $reader.Read()) {
            $result = [pscustomobject]@{
                LineId = [long] $reader['linea_id']
                PrinterId = [long] $reader['impresora_id']
                DeviceId = [long] $reader['dispositivo_id']
                EmployeeCount = [int] $reader['empleados_configurados']
                CredentialCount = [int] $reader['credenciales_configuradas']
                CorrelationId = [guid] $reader['correlacion_id']
            }
        }
    } while ($reader.NextResult())
    $reader.Close()
    $reader.Dispose()
    $packageCommand.Dispose()

    if ($null -eq $result) {
        throw 'El paquete 019 no devolvio su evidencia de validacion.'
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
        LineId = $result.LineId
        PrinterId = $result.PrinterId
        DeviceId = $result.DeviceId
        EmployeeCount = $result.EmployeeCount
        CredentialCount = $result.CredentialCount
        CorrelationId = $result.CorrelationId
        VerifiedBackupPath = if ($ValidateOnly) { $null } else { $VerifiedBackupPath }
    }
}
finally {
    if ($null -ne $transaction) {
        try { $transaction.Rollback() } catch { }
        $transaction.Dispose()
    }
    if ($connection.State -ne [Data.ConnectionState]::Closed) {
        $connection.Close()
    }
    $connection.Dispose()
}
