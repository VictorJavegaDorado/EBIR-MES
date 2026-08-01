[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$packagePath = Join-Path $repositoryRoot 'database\017A_lote_nav_ordenes_entrada.sql'
$sql = Get-Content -LiteralPath $packagePath -Raw

$required = @(
    "DB_NAME() <> N'EBIR_MES_TEST'",
    'SET XACT_ABORT ON',
    'BEGIN TRANSACTION',
    'ADD lote nvarchar(50) NULL',
    'CREATE PROCEDURE nav.registrar_lote_snapshot_orden',
    'CREATE PROCEDURE nav.promover_orden_entrada_con_lote_nav',
    "@lote_proporcionado_por = N''NAV:WS_CPP_OPLanzadas.Cod_Lote_Salida''",
    'GRANT EXECUTE ON OBJECT::nav.registrar_lote_snapshot_orden TO mes_runtime',
    'GRANT EXECUTE ON OBJECT::nav.promover_orden_entrada_con_lote_nav TO mes_runtime',
    'REVOKE EXECUTE ON OBJECT::nav.promover_orden_entrada FROM mes_runtime'
)

foreach ($token in $required) {
    if (-not $sql.Contains($token)) {
        throw "Falta el control obligatorio: $token"
    }
}

if ($sql -match '(?im)^\s*USE\s+' -or
    $sql -match '(?im)\bDROP\s+(TABLE|PROCEDURE|SCHEMA|DATABASE)\b' -or
    $sql -match '(?im)\bTRUNCATE\s+TABLE\b') {
    throw 'El paquete contiene una operacion fuera del patron seguro.'
}

Write-Host 'Revision estatica 017 correcta. No se ha ejecutado SQL.'
