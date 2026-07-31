[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$packagePath = Join-Path $repositoryRoot 'database\015A_bandeja_entrada_ordenes_nav.sql'
$sql = Get-Content -LiteralPath $packagePath -Raw

$required = @(
    "DB_NAME() <> N'EBIR_MES_TEST'",
    'SET XACT_ABORT ON',
    'BEGIN TRANSACTION',
    'CREATE TABLE nav.ordenes_entrada',
    'CREATE TABLE nav.lineas_orden_entrada',
    'CREATE TABLE nav.rutas_orden_entrada',
    'CREATE TABLE nav.componentes_orden_entrada',
    'CREATE TABLE nav.sincronizaciones_orden',
    'CREATE PROCEDURE nav.aplicar_snapshot_orden',
    'sys.sp_getapplock',
    'MES:NAVSYNC:CORR:',
    'MES:NAVSYNC:ORDER:',
    'THROW 55503',
    'GRANT EXECUTE ON OBJECT::nav.aplicar_snapshot_orden TO mes_runtime'
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

Write-Host 'Revision estatica 015 correcta. No se ha ejecutado SQL.'
