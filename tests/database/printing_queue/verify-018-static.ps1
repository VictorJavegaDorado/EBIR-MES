[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$packagePath = Join-Path $repositoryRoot 'database\018A_cola_impresion_worker.sql'
$sql = Get-Content -LiteralPath $packagePath -Raw
$required = @(
    "DB_NAME() <> N'EBIR_MES_TEST'",
    'SET XACT_ABORT ON',
    'BEGIN TRANSACTION',
    'numero_intentos int NOT NULL',
    'CREATE PROCEDURE imp.reservar_siguiente_trabajo_impresion',
    'CREATE PROCEDURE imp.completar_trabajo_impresion',
    'CREATE PROCEDURE imp.fallar_trabajo_impresion',
    "N''RESULTADO_DESCONOCIDO''",
    "numero_intentos >= 3 THEN N''ERROR''",
    'GRANT EXECUTE ON OBJECT::imp.reservar_siguiente_trabajo_impresion TO mes_runtime',
    'GRANT EXECUTE ON OBJECT::imp.completar_trabajo_impresion TO mes_runtime',
    'GRANT EXECUTE ON OBJECT::imp.fallar_trabajo_impresion TO mes_runtime'
)
foreach ($token in $required) {
    if (-not $sql.Contains($token)) { throw "Falta el control obligatorio: $token" }
}
if ($sql -match '(?im)^\s*USE\s+' -or
    $sql -match '(?im)\bDROP\s+(TABLE|PROCEDURE|SCHEMA|DATABASE)\b' -or
    $sql -match '(?im)\bTRUNCATE\s+TABLE\b' -or
    $sql -match '(?im)\bDELETE\s+FROM\b') {
    throw 'El paquete contiene una operacion fuera del patron seguro.'
}
Write-Host 'Revision estatica 018 correcta. No se ha ejecutado SQL.'
