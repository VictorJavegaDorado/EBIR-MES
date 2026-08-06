$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$scriptPath = Join-Path $root 'database\027A_contexto_salida_palet_codeunit.sql'
$sql = Get-Content -LiteralPath $scriptPath -Raw

$required = @(
    "IF DB_NAME() <> N'EBIR_MES_TEST'",
    'BEGIN TRANSACTION',
    'BEGIN CATCH',
    'ROLLBACK TRANSACTION',
    'CREATE OR ALTER PROCEDURE nav.reservar_siguiente_salida_palet',
    'o.lote',
    'e.codigo_nav',
    'l.codigo',
    'p.cerrado_por_empleado_id',
    'JOIN prod.sesiones_linea',
    'JOIN cfg.lineas',
    'JOIN seg.empleados',
    'GRANT EXECUTE ON OBJECT::nav.reservar_siguiente_salida_palet TO mes_runtime',
    "estado = N'PROCESANDO'"
)

foreach ($token in $required) {
    if (-not $sql.Contains($token)) {
        throw "Falta el contrato estatico requerido: $token"
    }
}

if ($sql -match '(?im)^\s*USE\s+' -or
    $sql -match '(?i)\b(?!EBIR_MES_TEST\b)[A-Za-z0-9_]+\.(?:nav|prod|cfg|seg)\.') {
    throw 'El paquete contiene una referencia de base no permitida.'
}

if ($sql -match '(?i)\b(?:DELETE|TRUNCATE|DROP)\b') {
    throw 'El paquete 027A no puede eliminar objetos ni datos.'
}

[pscustomobject]@{
    Package = '027A'
    DatabaseGuard = $true
    Transactional = $true
    NavContact = $false
    RequeuesOperations = $false
    AddsPalletContext = $true
}
