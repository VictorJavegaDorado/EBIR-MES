$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$scriptPath = Join-Path $root 'database\026A_cola_salida_palet_nav.sql'
$sql = Get-Content -LiteralPath $scriptPath -Raw

$required = @(
    "IF DB_NAME() <> N'EBIR_MES_TEST'",
    'BEGIN TRANSACTION',
    'BEGIN CATCH',
    'ROLLBACK TRANSACTION',
    'nav.reservar_siguiente_salida_palet',
    'nav.completar_salida_palet',
    'nav.fallar_salida_palet',
    "tipo = N''SALIDA_PALET''",
    "N''RESULTADO_DESCONOCIDO''",
    'numero_intentos < 3',
    'UPDLOCK, READPAST, ROWLOCK',
    'nav.confirmar_salida_palet',
    'GRANT EXECUTE ON OBJECT::nav.reservar_siguiente_salida_palet TO mes_runtime'
)

foreach ($token in $required) {
    if (-not $sql.Contains($token)) {
        throw "Falta el contrato estatico requerido: $token"
    }
}

if ($sql -match '(?im)^\s*USE\s+' -or
    $sql -match '(?i)\b(?!EBIR_MES_TEST\b)[A-Za-z0-9_]+\.(?:nav|prod|imp)\.') {
    throw 'El paquete contiene una referencia de base no permitida.'
}

[pscustomobject]@{
    Package = '026A'
    DatabaseGuard = $true
    Transactional = $true
    NavContact = $false
    RetryLimit = 3
    UnknownResultGuard = $true
}
