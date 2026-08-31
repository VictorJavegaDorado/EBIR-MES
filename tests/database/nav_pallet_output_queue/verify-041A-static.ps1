$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$migration = Join-Path $root 'database\041A_reconciliacion_tardia_generica.sql'
$sql = Get-Content -LiteralPath $migration -Raw

$required = @(
    "DB_NAME() <> N'EBIR_MES_TEST'",
    'CREATE OR ALTER PROCEDURE nav.reservar_siguiente_salida_palet',
    'CREATE OR ALTER PROCEDURE nav.fallar_salida_palet',
    '@solo_reconciliacion AS solo_reconciliacion',
    '@baseline_maximum_id AS baseline_maximum_id',
    "N''NavisionSoapPalletOutputSender''",
    "N''UnknownResult''",
    'numero_intentos < 12',
    "N''MultipleNewOutputs''",
    "N''ReconciliationTruncated''",
    '@continuar_reconciliacion',
    'GRANT EXECUTE ON OBJECT::nav.reservar_siguiente_salida_palet TO mes_runtime',
    'GRANT EXECUTE ON OBJECT::nav.fallar_salida_palet TO mes_runtime'
)

foreach ($token in $required) {
    if (-not $sql.Contains($token)) {
        throw "Falta el contrato estatico requerido: $token"
    }
}

$forbidden = @(
    'RegistrarSalidaFabricacion',
    'NAVISION2017',
    'EBIR_MES_PROD',
    'UPDATE OPENQUERY',
    'DELETE FROM nav.operaciones'
)

foreach ($token in $forbidden) {
    if ($sql.Contains($token)) {
        throw "El paquete contiene una operacion prohibida: $token"
    }
}

Write-Output 'OK verify-041A-static'
