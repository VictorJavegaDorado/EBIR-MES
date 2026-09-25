$ErrorActionPreference = 'Stop'

$package = Join-Path $PSScriptRoot '..\..\..\database\052A_seguimiento_solicitudes_material_mes.sql'
$text = Get-Content -LiteralPath $package -Raw

$required = @(
    "DB_NAME() <> N'EBIR_MES_TEST'",
    'CREATE OR ALTER PROCEDURE [log].listar_seguimiento_solicitudes_material_mes',
    '@sesion_linea_id bigint',
    'WITH EXECUTE AS OWNER',
    'TOP (10)',
    'FROM [log].solicitudes_reaprovisionamiento',
    'INNER JOIN nav.componentes_orden',
    'FROM aud.eventos',
    "a.tipo_evento = N''REAPROVISIONAMIENTO_SOLICITADO''",
    'GRANT EXECUTE',
    'TO mes_runtime',
    'BEGIN TRANSACTION',
    'COMMIT TRANSACTION',
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

if ($text -match 'GRANT\s+SELECT' -or $text -match 'TO\s+mes_runtime[\s\S]*aud\.eventos') {
    throw 'El paquete no debe conceder lectura directa sobre auditoria al runtime.'
}

Write-Host 'Validacion estatica 052A correcta.'
