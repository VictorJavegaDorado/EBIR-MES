$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$package = Join-Path $root 'deploy\nav\NAV-001D'
$readme = Get-Content -LiteralPath (Join-Path $package 'README.md') -Raw
$spec = Get-Content -LiteralPath (Join-Path $package 'CHANGE-SPECIFICATION.md') -Raw
$worker = Get-Content -LiteralPath (
    Join-Path $root 'src\backend\Ebir.Mes.Integrations\NavisionOutput\NavisionSoapPalletOutputSender.cs') -Raw
$options = Get-Content -LiteralPath (
    Join-Path $root 'src\backend\Ebir.Mes.Integrations\NavisionOutput\NavisionPalletOutputOptions.cs') -Raw
$settings = Get-Content -LiteralPath (
    Join-Path $root 'src\backend\Ebir.Mes.Worker\appsettings.json') -Raw

foreach ($token in @(
    'NAVISION2 / EbirTest / EBIR',
    'Codeunit | 82000 | WS Control Planta',
    'TriggerMesEntryNow',
    'MES-SOLO-SALIDAS-V1',
    'EBIR\NAVEBIR',
    'Job Queue - Enqueue',
    '00:00:00',
    '23:59:59',
    'Scheduled=FALSE',
    'Tras la unica llamada',
    '5,5 segundos')) {
    if (-not (($readme + $spec).Contains($token))) {
        throw "Falta el contrato NAV-001D: $token"
    }
}

foreach ($token in @(
    'TriggerMesEntryNow',
    'WS_CPP_ControlPlanta',
    'ImmediateRegistrationEnabled',
    'ImmediateRegistrationObservationDelays')) {
    if (-not (($worker + $options).Contains($token))) {
        throw "Falta el contrato MES de disparo inmediato: $token"
    }
}

$json = $settings | ConvertFrom-Json
if ($json.NavisionOutput.ImmediateRegistrationEnabled -ne $false) {
    throw 'El disparo inmediato debe estar desactivado por defecto.'
}
Write-Output 'OK verify-NAV-001D-static'
