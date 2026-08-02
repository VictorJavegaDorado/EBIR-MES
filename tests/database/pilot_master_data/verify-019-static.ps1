[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$packagePath = Join-Path $repositoryRoot 'database\019A_maestros_piloto_test.sql'
$installerPath = Join-Path $PSScriptRoot 'install-019.ps1'
$package = Get-Content -LiteralPath $packagePath -Raw
$installer = Get-Content -LiteralPath $installerPath -Raw

$requiredPackageTokens = @(
    "DB_NAME() <> N'EBIR_MES_TEST'",
    "OBJECT_ID(N'tempdb..#pilot_linea')",
    'BEGIN TRANSACTION',
    'BEGIN CATCH',
    'IF XACT_STATE() <> 0 ROLLBACK TRANSACTION',
    'DATALENGTH(rfid_busqueda) <> 32',
    "rol_codigo = N'OPERARIO'",
    "rol_codigo = N'SUPERVISOR'",
    'INSERT cfg.lineas',
    'INSERT cfg.impresoras',
    'INSERT cfg.dispositivos',
    'INSERT cfg.lineas_impresoras',
    'INSERT cfg.lineas_dispositivos',
    'INSERT seg.empleados_roles',
    'INSERT seg.credenciales_rfid',
    "N'MAESTROS_PILOTO_CONFIGURADOS'"
)
foreach ($token in $requiredPackageTokens) {
    if (-not $package.Contains($token)) {
        throw "Falta el control obligatorio del paquete 019: $token"
    }
}

$requiredInstallerTokens = @(
    "'SQL.EBIR.LOCAL\NAVISION2017'",
    "'EBIR_MES_TEST'",
    '$ConfirmAuthorizedExecution',
    '$ValidateOnly',
    '$transaction.Rollback()',
    "['Integrated Security'] = `$true",
    "['TrustServerCertificate'] = `$true",
    'Convert-HexToBytes',
    'La configuracion fisica y personal debe permanecer fuera del repositorio.'
)
foreach ($token in $requiredInstallerTokens) {
    if (-not $installer.Contains($token)) {
        throw "Falta el control obligatorio del instalador 019: $token"
    }
}

if ($package -match '(?im)^\s*USE\s+' -or
    $package -match '(?im)\bDROP\s+(TABLE|PROCEDURE|SCHEMA|DATABASE)\b' -or
    $package -match '(?im)\bTRUNCATE\s+TABLE\b' -or
    $package -match '(?im)\bDELETE\s+FROM\b') {
    throw 'El paquete 019 contiene una operacion fuera del patron seguro.'
}

if ($package -match '(?i)10\.\d+\.\d+\.\d+' -or
    $package -match '(?i)rfidLookupHex|LookupKey' -or
    $package -match '(?i)TOSHIBA') {
    throw 'El SQL 019 contiene valores fisicos o secretos que deben ser externos.'
}

Write-Host 'Revision estatica 019 correcta. No se ha ejecutado SQL.'
