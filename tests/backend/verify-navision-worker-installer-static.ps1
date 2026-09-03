$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$installer = Join-Path $root 'deploy\worker\Install-MesNavisionOutputWorker.ps1'
$preflight = Join-Path $root 'deploy\worker\Test-MesNavisionOutputWorkerQueuePreflight.ps1'
$source = Get-Content -LiteralPath $installer -Raw
$preflightSource = Get-Content -LiteralPath $preflight -Raw

$required = @(
    "[securestring]`$MesDatabaseConnectionString",
    '[switch]$QueuePreflightConfirmed',
    '[datetime]$QueuePreflightUtc',
    '$preflightAge.TotalMinutes -gt 2',
    "[string]`$ServiceName = 'MES NAV Worker'",
    "[string]`$PrintingServiceName = 'MES Worker'",
    'Worker__ServiceName=$ServiceName',
    'NavisionOutput__Enabled=true',
    'NavisionOutput__RunOnce=false',
    'Printing__Enabled=false',
    'EbirTest/WS/EBIR/Codeunit/WS_CPP_ControlPlanta',
    "InitialCatalog -ne 'EBIR_MES_TEST'",
    "DataSource -ne 'SQL.EBIR.LOCAL\NAVISION2017'",
    'Start-Service -Name $ServiceName'
)

foreach ($token in $required) {
    if (-not $source.Contains($token)) {
        throw "Falta el contrato estatico requerido: $token"
    }
}

$preflightRequired = @(
    "[string]`$ServerInstance = 'SQL.EBIR.LOCAL\NAVISION2017'",
    "[string]`$Database = 'EBIR_MES_TEST'",
    'Integrated Security=True',
    "DB_NAME() <> N'EBIR_MES_TEST'",
    'numero_intentos < 12',
    'DISCOVER_AFTER_BASELINE',
    "N'PENDIENTE'",
    "N'PROCESANDO'",
    "N'ERROR_REINTENTABLE'",
    "N'RESULTADO_DESCONOCIDO'",
    'Existen salidas NAV no terminales',
    'QueuePreflightUtc = [DateTime]::UtcNow'
)

foreach ($token in $preflightRequired) {
    if (-not $preflightSource.Contains($token)) {
        throw "Falta el contrato estatico requerido en el prevuelo: $token"
    }
}

if ($source.Contains('$connection.Open()')) {
    throw 'El instalador remoto no debe abrir SQL por WinRM.'
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

$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    $preflight,
    [ref]$tokens,
    [ref]$errors) | Out-Null
if ($errors.Count -ne 0) {
    throw ($errors | ForEach-Object Message | Out-String)
}

Write-Output 'OK verify-navision-worker-installer-static'
