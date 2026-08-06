$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$scriptPath = Join-Path $root 'database\026B_reencolar_salida_palet_405.sql'
$sql = Get-Content -LiteralPath $scriptPath -Raw

$required = @(
    "IF DB_NAME() <> N'EBIR_MES_TEST'",
    'BEGIN TRANSACTION',
    'BEGIN CATCH',
    'ROLLBACK TRANSACTION',
    'operacion_nav_id = 31',
    "n.estado = N'ERROR_DEFINITIVO'",
    'n.numero_intentos = 1',
    'n.identificador_externo IS NULL',
    'n.reservado_utc IS NULL',
    'n.reservado_por IS NULL',
    'codigo_http = 405',
    "JSON_VALUE(respuesta, '$.outcome') = N'PermanentFailure'",
    "JSON_VALUE(respuesta, '$.adapter') = N'NavisionODataV4PalletOutputSender'",
    "SET estado = N'PENDIENTE'",
    "N'NAV_SALIDA_REENCOLADA'",
    'INSERT aud.eventos',
    'IF @@ROWCOUNT <> 1'
)

foreach ($token in $required) {
    if (-not $sql.Contains($token)) {
        throw "Falta el contrato estatico requerido de 026B: $token"
    }
}

if ($sql -match '(?im)^\s*USE\s+' -or
    $sql -match '(?i)\b(?!EBIR_MES_TEST\b)[A-Za-z0-9_]+\.(?:nav|prod|aud)\.') {
    throw 'El paquete 026B contiene una referencia de base no permitida.'
}

if ($sql -match '(?i)https?://|WS_CPP_SalidasFabrica') {
    throw 'El paquete 026B no puede contactar ni configurar NAV.'
}

[pscustomobject]@{
    Package = '026B'
    DatabaseGuard = $true
    Transactional = $true
    ExactOperation = 31
    PreservesAttempt = $true
    Audit = $true
    NavContact = $false
}
