[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $PublishedApiDirectory,

    [Parameter(Mandatory = $true)]
    [guid] $CorrelationId,

    [Parameter(Mandatory = $true)]
    [string] $ResultPath,

    [string] $OrderNumber = '29516CI/1508',
    [string] $SqlServer = 'SQL.EBIR.LOCAL\NAVISION2017',
    [string] $Database = 'EBIR_MES_TEST',
    [string] $NavEnvironment = 'EBIRTEST',
    [string] $NavCompany = 'EBIR',
    [uri] $NavServiceRoot = 'http://NAVISION2.EBIR.LOCAL:7147/EbirTest/WS/',
    [ValidateRange(1024, 65535)]
    [int] $LocalPort = 50731,
    [switch] $ConfirmAuthorizedExecution
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ConfirmAuthorizedExecution) {
    throw 'La ejecucion exige -ConfirmAuthorizedExecution.'
}

if ($Database -cne 'EBIR_MES_TEST') {
    throw "Base no autorizada: $Database"
}

$authorizedNavServiceRoot = [uri] 'http://NAVISION2.EBIR.LOCAL:7147/EbirTest/WS/'
if ($NavServiceRoot.AbsoluteUri -cne $authorizedNavServiceRoot.AbsoluteUri) {
    throw "Raiz NAV no autorizada: $($NavServiceRoot.AbsoluteUri)"
}

if ($NavEnvironment -cne 'EBIRTEST' -or $NavCompany -cne 'EBIR') {
    throw "Entorno o empresa NAV no autorizados."
}

$windowsIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$identity = $windowsIdentity.Name
if ($windowsIdentity.User.Value -cne 'S-1-5-20') {
    throw "Identidad no autorizada para esta prueba: $identity"
}

$apiDirectory = [IO.Path]::GetFullPath($PublishedApiDirectory)
$apiDll = Join-Path $apiDirectory 'Ebir.Mes.Api.dll'
if (-not (Test-Path -LiteralPath $apiDll -PathType Leaf)) {
    throw "No existe la API publicada: $apiDll"
}

$resolvedResultPath = [IO.Path]::GetFullPath($ResultPath)
$allowedResultRoot = 'C:\MES\runtime\shared\temp\manual-nav-sync-'
if (-not $resolvedResultPath.StartsWith(
        $allowedResultRoot,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "Ruta de resultado no autorizada: $resolvedResultPath"
}

$resultDirectory = Split-Path -Parent $resolvedResultPath
$stdoutPath = Join-Path $resultDirectory 'api.stdout.log'
$stderrPath = Join-Path $resultDirectory 'api.stderr.log'
$process = $null
$result = [ordered]@{
    Status = 'FAILED'
    Identity = $identity
    CorrelationId = $CorrelationId
    Before = $null
    FirstResponse = $null
    SecondResponse = $null
    After = $null
    ErrorType = $null
    ErrorMessage = $null
    CompletedUtc = $null
}
$connectionString = "Data Source=$SqlServer;Initial Catalog=$Database;" +
    'Integrated Security=SSPI;Encrypt=True;TrustServerCertificate=True;' +
    'Application Name=EBIR MES controlled NAV sync'

function Get-InboundState {
    $connection = New-Object System.Data.SqlClient.SqlConnection $connectionString
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandTimeout = 30
        $command.CommandText = @'
SET NOCOUNT ON;
SELECT
    DB_NAME() AS DatabaseName,
    (SELECT COUNT_BIG(*) FROM nav.ordenes_entrada) AS InboundOrders,
    (SELECT COUNT_BIG(*) FROM nav.lineas_orden_entrada) AS InboundLines,
    (SELECT COUNT_BIG(*) FROM nav.rutas_orden_entrada) AS InboundRouting,
    (SELECT COUNT_BIG(*) FROM nav.componentes_orden_entrada) AS InboundComponents,
    (SELECT COUNT_BIG(*) FROM nav.sincronizaciones_orden) AS Synchronizations,
    (SELECT COUNT_BIG(*)
       FROM nav.ordenes_entrada o
       INNER JOIN nav.empresas e ON e.empresa_nav_id = o.empresa_nav_id
       INNER JOIN nav.entornos n ON n.entorno_nav_id = e.entorno_nav_id
      WHERE n.codigo = @environment
        AND e.codigo = @company
        AND o.numero_orden = @orderNumber) AS TargetOrders;
'@
        [void] $command.Parameters.Add(
            '@environment',
            [System.Data.SqlDbType]::NVarChar,
            30)
        $command.Parameters['@environment'].Value = $NavEnvironment
        [void] $command.Parameters.Add(
            '@company',
            [System.Data.SqlDbType]::NVarChar,
            50)
        $command.Parameters['@company'].Value = $NavCompany
        [void] $command.Parameters.Add(
            '@orderNumber',
            [System.Data.SqlDbType]::NVarChar,
            30)
        $command.Parameters['@orderNumber'].Value = $OrderNumber
        $reader = $command.ExecuteReader()
        if (-not $reader.Read()) {
            throw 'La consulta de estado SQL no devolvio ninguna fila.'
        }

        return [ordered]@{
            Database = [string] $reader['DatabaseName']
            InboundOrders = [long] $reader['InboundOrders']
            InboundLines = [long] $reader['InboundLines']
            InboundRouting = [long] $reader['InboundRouting']
            InboundComponents = [long] $reader['InboundComponents']
            Synchronizations = [long] $reader['Synchronizations']
            TargetOrders = [long] $reader['TargetOrders']
        }
    }
    finally {
        if ($connection.State -ne 'Closed') {
            $connection.Close()
        }

        $connection.Dispose()
    }
}

try {
    $result.Before = Get-InboundState
    $env:ASPNETCORE_URLS = "http://127.0.0.1:$LocalPort"
    $env:ASPNETCORE_ENVIRONMENT = 'ManualNavSync'
    $env:ConnectionStrings__MesDatabase = $connectionString
    $env:Navision__ProductionOrderSynchronizationEnabled = 'true'
    $env:Navision__Environment = $NavEnvironment
    $env:Navision__Company = $NavCompany
    $env:Navision__ServiceRoot = $NavServiceRoot.AbsoluteUri
    $env:Navision__RequestTimeoutSeconds = '30'
    $env:Navision__MaximumReadAttempts = '3'

    $process = Start-Process `
        -FilePath 'C:\Program Files\dotnet\dotnet.exe' `
        -ArgumentList ('"' + $apiDll + '"') `
        -WorkingDirectory $apiDirectory `
        -WindowStyle Hidden `
        -PassThru `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath

    $healthy = $false
    for ($attempt = 0; $attempt -lt 45; $attempt++) {
        if ($process.HasExited) {
            throw "La API temporal termino con codigo $($process.ExitCode)."
        }

        try {
            $health = Invoke-RestMethod `
                -Uri "http://127.0.0.1:$LocalPort/health/live" `
                -TimeoutSec 2
            if ($health.status -eq 'ok') {
                $healthy = $true
                break
            }
        }
        catch {
            Start-Sleep -Milliseconds 500
        }
    }

    if (-not $healthy) {
        throw 'La API temporal no alcanzo el estado saludable.'
    }

    $payload = @{
        orderNumber = $OrderNumber
        correlationId = $CorrelationId
    } | ConvertTo-Json -Compress
    $endpoint = "http://127.0.0.1:$LocalPort/api/admin/production-orders/synchronize"
    $first = Invoke-RestMethod `
        -Method Post `
        -Uri $endpoint `
        -ContentType 'application/json' `
        -Body $payload `
        -TimeoutSec 120
    $second = Invoke-RestMethod `
        -Method Post `
        -Uri $endpoint `
        -ContentType 'application/json' `
        -Body $payload `
        -TimeoutSec 120

    $result.FirstResponse = [ordered]@{
        InboundOrderId = [long] $first.inboundOrderId
        Outcome = [string] $first.outcome
        CorrelationId = [string] $first.correlationId
    }
    $result.SecondResponse = [ordered]@{
        InboundOrderId = [long] $second.inboundOrderId
        Outcome = [string] $second.outcome
        CorrelationId = [string] $second.correlationId
    }
    $result.After = Get-InboundState

    if ($result.Before.Database -cne 'EBIR_MES_TEST' -or
        $result.FirstResponse.Outcome -notin @(
            'CREADA',
            'ACTUALIZADA',
            'SIN_CAMBIOS') -or
        $result.FirstResponse.InboundOrderId -ne
            $result.SecondResponse.InboundOrderId -or
        $result.FirstResponse.Outcome -cne $result.SecondResponse.Outcome -or
        $result.After.TargetOrders -ne 1 -or
        $result.After.Synchronizations -ne
            ($result.Before.Synchronizations + 1)) {
        throw 'Las aserciones de sincronizacion manual no se cumplieron.'
    }

    $result.Status = 'SUCCEEDED'
}
catch {
    $result.ErrorType = $_.Exception.GetType().FullName
    $result.ErrorMessage = $_.Exception.Message
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $process.WaitForExit()
    }

    $result.CompletedUtc = [DateTime]::UtcNow.ToString('O')
    $result | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $resolvedResultPath -Encoding UTF8
}

if ($result.Status -ne 'SUCCEEDED') {
    exit 1
}
