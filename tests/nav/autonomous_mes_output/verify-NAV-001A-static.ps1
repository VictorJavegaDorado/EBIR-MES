$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$package = Join-Path $root 'deploy\nav\NAV-001A'
$readme = Get-Content -LiteralPath (Join-Path $package 'README.md') -Raw
$spec = Get-Content -LiteralPath (Join-Path $package 'CHANGE-SPECIFICATION.md') -Raw
$matrix = Get-Content -LiteralPath (Join-Path $package 'TEST-MATRIX.md') -Raw
$runbook = Get-Content -LiteralPath (Join-Path $package 'PILOT-RUNBOOK.md') -Raw
$all = $readme + "`n" + $spec + "`n" + $matrix + "`n" + $runbook

$required = @(
    'INSTALADO_COMPILADO_EBIRTEST_SIN_EJECUCION',
    'EbirTest',
    'Tabla 50013',
    'Pagina 50036',
    'Report 50056',
    'Codeunit 60103',
    'Codeunit 82000',
    'campo 700',
    'Origen MES',
    'OpenClosePalletMES',
    'TryClaimRegistration',
    'SoloSalidasMES',
    'External Document No.',
    'ImprimirAlRegistrar',
    'SoloSalidasMES=TRUE',
    'no cambiar automaticamente `Procesando` a `Pendiente`',
    'produccion queda prohibida'
)

foreach ($token in $required) {
    if (-not $all.Contains($token)) {
        throw "Falta el contrato estatico requerido: $token"
    }
}

$expectedHashes = @(
    'EA8A15BEB92E0AFE77C7BF3F99A35DE765BB2EBD2961EFDDF41150C315CDE692',
    'B9B7F66E5B7F3C55F63D7C48F4C422FF94B69307782319812D7348F9BC2FBC9B',
    '46C43DEC8BBBE519339C9D09118A62EC4B94FE37231D82F4CEBF69410283CA34',
    '602A554617552F6C9542598FEE24335EA013B57A9EA5D91B82BB451C6A17F002',
    '9929C5C2F8766B530B2FC231DAC72035CE5F68EE5990C70625F936B2FD491676'
)

foreach ($hash in $expectedHashes) {
    if (-not $readme.Contains($hash)) {
        throw "Falta el hash de baseline: $hash"
    }
}

$unexpectedFiles = Get-ChildItem -LiteralPath $package -Recurse -File |
    Where-Object { $_.Extension -notin @('.md') }
if ($unexpectedFiles) {
    throw 'El paquete NAV contiene artefactos distintos de documentacion revisable.'
}

if ($all -match '(?im)^\s*OBJECT\s+(?:Table|Page|Report|Codeunit)\b') {
    throw 'El paquete contiene una exportacion de objeto NAV protegida.'
}

if ($all -match '(?i)password\s*=|connectionstring\s*=|clientsecret\s*=|BEGIN (?:RSA |OPENSSH )?PRIVATE KEY') {
    throw 'El paquete contiene una configuracion o secreto prohibido.'
}

if ($all -match '(?<!\d)(?:\d{1,3}\.){3}\d{1,3}(?!\d)') {
    throw 'El paquete contiene una direccion de red explicita.'
}

if ($spec -notmatch '(?is)bloquear la tabla.*releer.*Pendiente.*Procesando' -or
    $spec -notmatch '(?is)cero movimientos.*contabilizacion normal.*conjunto unico.*Registrado.*ambiguo.*no contabilizar') {
    throw 'La especificacion no define reclamacion atomica e idempotencia exacta.'
}

if ($spec -notmatch '(?is)Origen MES=FALSE.*Origen MES=TRUE' -or
    $spec -notmatch '(?is)ImprimirAlRegistrar.*Origen MES=FALSE.*nunca imprimir.*Origen MES=TRUE') {
    throw 'La compatibilidad heredada o la barrera de impresion MES no son explicitas.'
}

[pscustomobject]@{
    Package = 'NAV-001A'
    Status = 'INSTALADO_COMPILADO_EBIRTEST_SIN_EJECUCION'
    ExternalConnections = $false
    ProtectedObjectExports = $false
    BaselineHashes = $expectedHashes.Count
    NavObjectsSpecified = 5
    AtomicClaim = $true
    ExactReconciliation = $true
    MesNavPrinting = $false
}
