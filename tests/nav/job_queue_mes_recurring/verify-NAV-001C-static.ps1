$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$package = Join-Path $root 'deploy\nav\NAV-001C'
$files = @(
    'README.md',
    'CONFIGURATION-SPECIFICATION.md',
    'TEST-MATRIX.md',
    'PILOT-RUNBOOK.md'
)

foreach ($name in $files) {
    $path = Join-Path $package $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Falta el archivo NAV-001C requerido: $name"
    }
}

$content = ($files | ForEach-Object {
    Get-Content -LiteralPath (Join-Path $package $_) -Raw
}) -join "`n"

$required = @(
    'NAVISION2',
    'EbirTest',
    'EBIR_MES_TEST',
    'Codeunit 50009',
    'MES - Registro autonomo salidas',
    'MES-SOLO-SALIDAS-V1',
    'lunes a domingo',
    '00:00:00',
    '23:59:59',
    'Un minuto',
    'En espera',
    'Listo',
    'MES NAV Worker',
    '041A',
    'No se modifica',
    'rollback'
)

foreach ($token in $required) {
    if (-not $content.Contains($token)) {
        throw "Falta el contrato NAV-001C requerido: $token"
    }
}

$forbiddenFiles = Get-ChildItem -LiteralPath $package -File | Where-Object {
    $_.Extension -in '.txt', '.fob'
}
if ($forbiddenFiles) {
    throw 'NAV-001C no puede contener objetos NAV en Git.'
}

$forbidden = @(
    'EBIR_MES_PROD',
    'SetStatus(Listo)',
    'RunJobQueueEntryOnce',
    'UPDATE OPENQUERY',
    'OBJECT Codeunit',
    'OBJECT Table'
)
foreach ($token in $forbidden) {
    if ($content.Contains($token)) {
        throw "NAV-001C contiene una operacion prohibida: $token"
    }
}

Write-Output 'OK verify-NAV-001C-static'
