[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$packagePath = Join-Path $repositoryRoot 'database\022A_formato_palet_pok.sql'
$sql = Get-Content -LiteralPath $packagePath -Raw -Encoding utf8

$required = @(
    "DB_NAME() <> N'EBIR_MES_TEST'",
    'SET XACT_ABORT ON',
    'BEGIN TRANSACTION',
    'CREATE TABLE nav.formatos_palet_orden_entrada',
    'CREATE PROCEDURE nav.registrar_formato_palet_snapshot_orden',
    "JSON_VALUE(@snapshot_json, ''$.palletFormat.productNumber'')",
    "''$.palletFormat.quantityPerUnitMeasure''",
    'ALTER PROCEDURE nav.promover_orden_entrada_con_lote_nav',
    'prod.formatos_palet_orden',
    "@resultado IN (N''CREADA'', N''SIN_CAMBIOS'')",
    'THROW 55616',
    'GRANT EXECUTE ON OBJECT::nav.registrar_formato_palet_snapshot_orden TO mes_runtime'
)

foreach ($token in $required) {
    if (-not $sql.Contains($token)) {
        throw "Falta el control obligatorio: $token"
    }
}

if ($sql -match '(?im)^\s*USE\s+' -or
    $sql -match '(?im)\bDROP\s+(TABLE|PROCEDURE|SCHEMA|DATABASE)\b' -or
    $sql -match '(?im)\bTRUNCATE\s+TABLE\b' -or
    $sql -match '(?im)\b(INSERT|UPDATE|DELETE)\s+.*NAVISION') {
    throw 'El paquete contiene una operacion fuera del patron seguro.'
}

Write-Host 'Revision estatica 022 correcta. No se ha ejecutado SQL.'
