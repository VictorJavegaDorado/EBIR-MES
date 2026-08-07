[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$packagePath = Join-Path $repositoryRoot 'database\035A_finalizar_orden_produccion.sql'
$sql = Get-Content -LiteralPath $packagePath -Raw -Encoding utf8

$required = @(
    "DB_NAME() <> N'EBIR_MES_TEST'",
    'SET XACT_ABORT ON',
    'BEGIN TRANSACTION',
    'CREATE OR ALTER PROCEDURE prod.finalizar_orden_produccion',
    "@estado_orden <> N''PENDIENTE_CIERRE''",
    "@estado_sesion <> N''SIN_OPERARIOS''",
    "n.estado = N''CONFIRMADA''",
    "e.estado IN (N''LISTA'', N''IMPRESA'')",
    "SET estado = N''FINALIZADA''",
    "SET estado = N''ORDEN_COMPLETADA''",
    "estado = N''LIBRE''",
    'GRANT EXECUTE ON OBJECT::prod.finalizar_orden_produccion TO mes_runtime'
)

foreach ($token in $required) {
    if (-not $sql.Contains($token)) {
        throw "Falta el control obligatorio: $token"
    }
}

if ($sql -match '(?im)^\s*USE\s+' -or
    $sql -match '(?im)\bDROP\s+(TABLE|PROCEDURE|SCHEMA|DATABASE)\b' -or
    $sql -match '(?im)\bTRUNCATE\s+TABLE\b' -or
    $sql.Contains("e.estado <> N''IMPRESA''")) {
    throw 'El paquete contiene una operacion o acoplamiento fuera del patron seguro.'
}

Write-Host 'Revision estatica 035A correcta. No se ha ejecutado SQL.'
