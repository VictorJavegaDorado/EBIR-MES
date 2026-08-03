[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$packagePath = Join-Path $repositoryRoot 'database\020A_rotacion_credenciales_rfid_piloto.sql'
$installerPath = Join-Path $PSScriptRoot 'install-020.ps1'
$package = Get-Content -LiteralPath $packagePath -Raw
$installer = Get-Content -LiteralPath $installerPath -Raw

$requiredPackageTokens = @(
    "DB_NAME() <> N'EBIR_MES_TEST'",
    "OBJECT_ID(N'tempdb..#pilot_rfid_rotations')",
    'BEGIN TRANSACTION',
    'BEGIN CATCH',
    'IF XACT_STATE() <> 0 ROLLBACK TRANSACTION',
    'UPDATE c',
    'motivo_baja',
    'INSERT seg.credenciales_rfid',
    "N'CREDENCIALES_RFID_ROTADAS'",
    "N'PAQUETE_020'",
    'DATALENGTH(rfid_busqueda) <> 32'
)
foreach ($token in $requiredPackageTokens) {
    if (-not $package.Contains($token)) { throw "Falta el control obligatorio del paquete 020: $token" }
}

$requiredInstallerTokens = @(
    "'SQL.EBIR.LOCAL\NAVISION2017'",
    "'EBIR_MES_TEST'",
    '$ConfirmAuthorizedExecution',
    '$ValidateOnly',
    '$transaction.Rollback()',
    '$VerifiedBackupPath',
    'Convert-HexToBytes',
    'La configuracion RFID debe permanecer fuera del repositorio.'
)
foreach ($token in $requiredInstallerTokens) {
    if (-not $installer.Contains($token)) { throw "Falta el control obligatorio del instalador 020: $token" }
}

if ($package -match '(?im)^\s*USE\s+' -or
    $package -match '(?im)\bDROP\s+(TABLE|PROCEDURE|SCHEMA|DATABASE)\b' -or
    $package -match '(?im)\bTRUNCATE\s+TABLE\b' -or
    $package -match '(?im)\bDELETE\s+FROM\b') {
    throw 'El paquete 020 contiene una operacion fuera del patron seguro.'
}
if ($package -match '(?i)rfidLookupHex|LookupKey' -or
    $package -match '(?i)\b[0-9A-F]{64}\b' -or
    $package -match '(?i)10\.\d+\.\d+\.\d+') {
    throw 'El SQL 020 contiene valores fisicos o secretos que deben ser externos.'
}

Write-Host 'Revision estatica 020 correcta. No se ha ejecutado SQL.'
