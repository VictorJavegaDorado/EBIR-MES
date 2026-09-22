$ErrorActionPreference = 'Stop'

$package = Join-Path $PSScriptRoot '..\..\..\database\051A_confirmar_reconciliacion_tardia_salida_palet_122.sql'
$text = Get-Content -LiteralPath $package -Raw

$required = @(
    "DB_NAME() <> N'EBIR_MES_TEST'",
    'operacion_nav_id=122',
    "identificador_externo=N'26926'",
    'numero_intentos=24',
    "JSON_VALUE(respuesta,'$.reason')=N'OutputStateNotRegistered'",
    'palet_id=111',
    'etiqueta_id=113',
    'EXEC nav.confirmar_salida_palet',
    'numero_intentos=25',
    "estado=N'LISTA'",
    "estado=N'PENDIENTE'",
    'BEGIN TRANSACTION',
    'UPDLOCK,HOLDLOCK',
    'ROLLBACK TRANSACTION'
)

foreach ($token in $required) {
    if (-not $text.Contains($token)) {
        throw "Falta la guarda requerida: $token"
    }
}

if ($text -match '\bUSE\b' -or $text -match 'EBIR_MES(?!_TEST)') {
    throw 'El paquete contiene una referencia de base no permitida.'
}

Write-Host 'Validación estática 051A correcta.'
