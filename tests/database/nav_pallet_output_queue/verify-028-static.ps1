$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$scriptPath = Join-Path $root 'database\028A_reconciliacion_salida_palet_continua.sql'
$sql = Get-Content -LiteralPath $scriptPath -Raw

$required = @(
    "IF DB_NAME() <> N'EBIR_MES_TEST'",
    'BEGIN TRANSACTION',
    'BEGIN CATCH',
    'ROLLBACK TRANSACTION',
    'CREATE OR ALTER PROCEDURE nav.reservar_siguiente_salida_palet',
    'n.identificador_externo',
    "estado = N''RESULTADO_DESCONOCIDO''",
    'DATEADD(SECOND, 10',
    'THROW 51412',
    'La salida del palet anterior no esta confirmada en NAV.',
    'IF @es_ultimo = 1',
    'p.es_ultimo = 0',
    'GRANT EXECUTE ON OBJECT::nav.reservar_siguiente_salida_palet TO mes_runtime'
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

if ($sql -match '(?i)\b(?:TRUNCATE|DROP)\b') {
    throw 'El paquete 028A no puede eliminar objetos ni datos.'
}

[pscustomobject]@{
    Package = '028A'
    DatabaseGuard = $true
    Transactional = $true
    NavContact = $false
    ReconcilesByExternalIdentifier = $true
    KeepsNonFinalPalletProductionActive = $true
    BlocksOverlappingPalletClosures = $true
}
