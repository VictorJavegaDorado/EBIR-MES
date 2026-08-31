$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$migration = Join-Path $root 'database\042A_retirar_creacion_cierre_fl.sql'
$sql = Get-Content -LiteralPath $migration -Raw

$required = @(
    "DB_NAME() <> N'EBIR_MES_TEST'",
    'CREATE OR ALTER PROCEDURE imp.confirmar_trabajo_impresion',
    "motivo_bloqueo=N''ORDEN_PENDIENTE_CIERRE''",
    'prod.recursos_efectivos_sesion',
    "@tipo_evento=N''ETIQUETA_IMPRESA''",
    'GRANT EXECUTE ON OBJECT::imp.confirmar_trabajo_impresion TO mes_runtime'
)

foreach ($token in $required) {
    if (-not $sql.Contains($token)) {
        throw "Falta el contrato estatico requerido: $token"
    }
}

$published = [regex]::Match(
    $sql,
    "CREATE OR ALTER PROCEDURE imp\.confirmar_trabajo_impresion[\s\S]+?END;'"
).Value
if ([string]::IsNullOrWhiteSpace($published)) {
    throw 'No se pudo aislar la definicion publicada.'
}

foreach ($token in @('MES:CIERRE_FL:', "N''CIERRE_FL''", 'INSERT nav.operaciones')) {
    if ($published.Contains($token)) {
        throw "El contrato publicado conserva una operacion obsoleta: $token"
    }
}

Write-Output 'OK verify-042A-static'
