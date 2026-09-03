$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$installer = Join-Path $root 'deploy\worker\Install-MesNavisionOutputWorker.ps1'
$source = Get-Content -LiteralPath $installer -Raw

$required = @(
    "[securestring]`$MesDatabaseConnectionString",
    "[string]`$ServiceName = 'MES NAV Worker'",
    "[string]`$PrintingServiceName = 'MES Worker'",
    'Worker__ServiceName=$ServiceName',
    'NavisionOutput__Enabled=true',
    'NavisionOutput__RunOnce=false',
    'Printing__Enabled=false',
    'EbirTest/WS/EBIR/Codeunit/WS_CPP_ControlPlanta',
    "InitialCatalog -ne 'EBIR_MES_TEST'",
    "DataSource -ne 'SQL.EBIR.LOCAL\NAVISION2017'",
    'DISCOVER_AFTER_BASELINE',
    'Existen salidas NAV no terminales',
    'Start-Service -Name $ServiceName'
)

foreach ($token in $required) {
    if (-not $source.Contains($token)) {
        throw "Falta el contrato estatico requerido: $token"
    }
}

$forbidden = @(
    'EBIR_MES_PROD',
    "'Printing__Enabled=true',",
    'NavisionOutput__RunOnce=true',
    'RegistrarSalidaFabricacion',
    'Password='
)

foreach ($token in $forbidden) {
    if ($source.Contains($token)) {
        throw "El instalador contiene una operacion prohibida: $token"
    }
}

$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    $installer,
    [ref]$tokens,
    [ref]$errors) | Out-Null
if ($errors.Count -ne 0) {
    throw ($errors | ForEach-Object Message | Out-String)
}

Write-Output 'OK verify-navision-worker-installer-static'
