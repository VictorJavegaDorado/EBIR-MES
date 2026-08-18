$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$package = Join-Path $repoRoot 'deploy\nav\NAV-001B'

$requiredFiles = @(
    'README.md',
    'CHANGE-SPECIFICATION.md',
    'TEST-MATRIX.md',
    'PILOT-RUNBOOK.md'
)

foreach ($name in $requiredFiles) {
    $path = Join-Path $package $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing NAV-001B package file: $name"
    }
}

$unexpected = @(
    Get-ChildItem -LiteralPath $package -Recurse -File |
        Where-Object { $_.Extension -ne '.md' }
)
if ($unexpected.Count -ne 0) {
    throw 'NAV-001B must not contain NAV objects, binaries or configuration.'
}

$all = ($requiredFiles | ForEach-Object {
    Get-Content -LiteralPath (Join-Path $package $_) -Raw
}) -join "`n"

$requiredTokens = @(
    'PREPARADO_NO_MATERIALIZADO',
    'OBJECT_ID_PENDING_INVENTORY',
    'EbirTest',
    'Report 50056',
    'Table 472',
    'SetSoloSalidasMES',
    'EnsureStoppedMesEntry',
    'MES-SOLO-SALIDAS-V1',
    'CREATED_ON_HOLD',
    'EXISTS_ON_HOLD',
    'En espera',
    'WS_MES_JobQueueAdmin',
    'Page 672',
    'RunJobQueueEntryOnce'
)

foreach ($token in $requiredTokens) {
    if (-not $all.Contains($token)) {
        throw "NAV-001B is missing required token: $token"
    }
}

$forbiddenPatterns = @(
    '(?i)BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY',
    '(?i)password\s*[:=]',
    '(?i)credential\.xml',
    '(?i)Data Source\s*=',
    '(?i)Initial Catalog\s*=',
    '(?i)User ID\s*=',
    '(?i)Pwd\s*='
)

foreach ($pattern in $forbiddenPatterns) {
    if ($all -match $pattern) {
        throw "NAV-001B contains forbidden material matching: $pattern"
    }
}

$unexpectedFiveDigitIds = @(
    [regex]::Matches($all, '\b\d{5}\b') |
        ForEach-Object { $_.Value } |
        Where-Object { $_ -ne '50056' } |
        Sort-Object -Unique
)
if ($unexpectedFiveDigitIds.Count -ne 0) {
    throw "NAV-001B assigns an unverified object ID: $($unexpectedFiveDigitIds -join ',')"
}

$spec = Get-Content -LiteralPath (
    Join-Path $package 'CHANGE-SPECIFICATION.md'
) -Raw

if ($spec -notmatch '(?is)bloquear la Table 472.*contar el conjunto completo.*mas de una coincidencia, abortar' -or
    $spec -notmatch '(?is)SetSoloSalidasMES\(TRUE\).*desactivar la request page' -or
    -not $spec.Contains('La funcion no llama al Report 50056') -or
    -not $spec.Contains('no cambia el estado a `Listo`') -or
    $spec -notmatch '(?s)no crea\s+tareas programadas') {
    throw 'NAV-001B does not prove atomic creation and execution separation.'
}

[pscustomobject]@{
    Package = 'NAV-001B'
    Status = 'PREPARADO_NO_MATERIALIZADO'
    ExternalConnections = $false
    ProtectedObjectExports = $false
    ObjectIdResolved = $false
    GenericJobQueuePagePublished = $false
    SqlNavWrites = $false
    AdministrativeCallExecutesReport = $false
}
