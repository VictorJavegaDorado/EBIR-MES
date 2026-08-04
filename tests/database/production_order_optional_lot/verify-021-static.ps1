[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$packagePath = Join-Path $repositoryRoot 'database\021A_lote_salida_opcional.sql'
$sql = Get-Content -LiteralPath $packagePath -Raw -Encoding utf8

$required = @(
    "DB_NAME() <> N'EBIR_MES_TEST'",
    'SET XACT_ABORT ON',
    'BEGIN TRANSACTION',
    'ALTER TABLE nav.promociones_orden DROP CONSTRAINT CK_nav_promociones_lote',
    'ALTER TABLE prod.ordenes DROP CONSTRAINT CK_prod_ordenes_lote',
    'ALTER PROCEDURE nav.registrar_lote_snapshot_orden',
    'ALTER PROCEDURE nav.promover_orden_entrada_con_lote_nav',
    'OBJECT_DEFINITION(OBJECT_ID(N''nav.promover_orden_entrada'', N''P''))',
    'ALTER PROCEDURE nav.promover_orden_entrada',
    "LTRIM(RTRIM(ISNULL(@lote, N'''')));",
    "@lote_proporcionado_por = N''NAV:WS_CPP_OPLanzadas.Cod_Lote_Salida''"
)

foreach ($token in $required) {
    if (-not $sql.Contains($token)) {
        throw "Falta el control obligatorio: $token"
    }
}

if ($sql.Contains('NAV_PRODUCTION_ORDER_LOT_REQUIRED') -or
    $sql -match '(?im)^\s*USE\s+' -or
    $sql -match '(?im)\bDROP\s+(TABLE|PROCEDURE|SCHEMA|DATABASE)\b' -or
    $sql -match '(?im)\bTRUNCATE\s+TABLE\b') {
    throw 'El paquete contiene una operacion o contrato fuera del patron seguro.'
}

Write-Host 'Revision estatica 021 correcta. No se ha ejecutado SQL.'