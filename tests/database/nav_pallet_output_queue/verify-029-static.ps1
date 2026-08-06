$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$scriptPath = Join-Path $root 'database\029A_reencolar_salida_palet_32_ciclo_bulto.sql'
$sql = Get-Content -LiteralPath $scriptPath -Raw

$required = @(
    "IF DB_NAME() <> N'EBIR_MES_TEST'",
    'BEGIN TRANSACTION',
    'BEGIN CATCH',
    'ROLLBACK TRANSACTION',
    'operacion_nav_id = 32',
    "estado = N'RESULTADO_DESCONOCIDO'",
    'numero_intentos = 1',
    'identificador_externo IS NULL',
    'codigo_http = 500',
    "JSON_VALUE(respuesta, '$.reason') = N'SoapHttpUncertain'",
    "JSON_VALUE(respuesta, '$.baselineMaximumId')) = 26837",
    "SET estado = N'PENDIENTE'",
    "N'NAV_SALIDA_REENCOLADA'",
    'p.palet_id = 22',
    'p.numero_palet = 2',
    'p.cantidad_buena = 20'
)

foreach ($token in $required) {
    if (-not $sql.Contains($token)) {
        throw "Falta el contrato estatico requerido: $token"
    }
}

if ($sql -match '(?im)^\s*USE\s+' -or
    $sql -match '(?i)\b(?!EBIR_MES_TEST\b)[A-Za-z0-9_]+\.(?:nav|prod|cfg|seg|aud)\.') {
    throw 'El paquete contiene una referencia de base no permitida.'
}

if ($sql -match '(?i)\b(?:TRUNCATE|DROP|DELETE)\b') {
    throw 'El paquete 029A no puede eliminar objetos ni datos.'
}

[pscustomobject]@{
    Package = '029A'
    DatabaseGuard = $true
    Transactional = $true
    NavContact = $false
    ExactOperation = 32
    PreservesAttemptHistory = $true
    Audited = $true
}
