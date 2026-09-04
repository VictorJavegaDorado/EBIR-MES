$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$path=Join-Path $root 'database\046A_recuperacion_persistente_palet.sql'
$text=Get-Content -LiteralPath $path -Raw
$required=@(
    "DB_NAME() <> N'EBIR_MES_TEST'",
    "estado=N'PROCESANDO'",
    'n.numero_intentos BETWEEN 12 AND 23',
    '@numero_intento < 24',
    'CREATE OR ALTER PROCEDURE nav.solicitar_reconciliacion_salida_palet',
    "@estado<>N''RESULTADO_DESCONOCIDO'' OR @intentos<>12",
    "N''RECONCILIATION_ONLY'' AS mode",
    "N''RECONCILIACION_NAV_SOLICITADA''",
    'GRANT EXECUTE ON OBJECT::nav.solicitar_reconciliacion_salida_palet TO mes_runtime'
)
foreach($token in $required){if(-not $text.Contains($token)){throw "Falta contrato 046A: $token"}}
$forbidden=@('RegistrarSalidaFabricacion','INSERT nav.operaciones','DELETE FROM nav.operaciones')
foreach($token in $forbidden){if($text.Contains($token)){throw "Contrato peligroso en 046A: $token"}}
Write-Host '046A static verification passed.'
