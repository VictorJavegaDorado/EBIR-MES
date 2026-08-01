[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $PublishedApiDirectory,
    [Parameter(Mandatory = $true)] [long] $InboundOrderId,
    [Parameter(Mandatory = $true)] [string] $OperationNumber,
    [Parameter(Mandatory = $true)] [guid] $CorrelationId,
    [Parameter(Mandatory = $true)] [string] $ResultPath,
    [string] $SqlServer = 'SQL.EBIR.LOCAL\NAVISION2017',
    [string] $Database = 'EBIR_MES_TEST',
    [ValidateRange(1024, 65535)] [int] $LocalPort = 50733,
    [switch] $ConfirmAuthorizedExecution
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $ConfirmAuthorizedExecution) { throw 'La ejecucion exige -ConfirmAuthorizedExecution.' }
if ($Database -cne 'EBIR_MES_TEST') { throw "Base no autorizada: $Database" }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if ($identity.User.Value -cne 'S-1-5-20') {
    throw "Identidad no autorizada para esta prueba: $($identity.Name)"
}

$apiDirectory = [IO.Path]::GetFullPath($PublishedApiDirectory)
$apiDll = Join-Path $apiDirectory 'Ebir.Mes.Api.dll'
if (-not (Test-Path -LiteralPath $apiDll -PathType Leaf)) { throw "No existe la API: $apiDll" }
$resolvedResultPath = [IO.Path]::GetFullPath($ResultPath)
$allowedRoot = 'C:\MES\runtime\shared\temp\manual-nav-promotion-'
if (-not $resolvedResultPath.StartsWith($allowedRoot,[StringComparison]::OrdinalIgnoreCase)) {
    throw "Ruta de resultado no autorizada: $resolvedResultPath"
}

$resultDirectory = Split-Path -Parent $resolvedResultPath
$stdoutPath = Join-Path $resultDirectory 'api.stdout.log'
$stderrPath = Join-Path $resultDirectory 'api.stderr.log'
$connectionString = "Data Source=$SqlServer;Initial Catalog=$Database;" +
    'Integrated Security=SSPI;Encrypt=True;TrustServerCertificate=True;' +
    'Application Name=EBIR MES controlled NAV promotion'
$process = $null
$result = [ordered]@{
    Status='FAILED';Identity=$identity.Name;CorrelationId=$CorrelationId
    Before=$null;FirstResponse=$null;SecondResponse=$null;After=$null
    ErrorType=$null;ErrorMessage=$null;CompletedUtc=$null
}

function Get-PromotionState {
    $connection = New-Object System.Data.SqlClient.SqlConnection $connectionString
    try {
        $connection.Open();$command=$connection.CreateCommand();$command.CommandTimeout=30
        $command.CommandText=@'
SELECT o.numero_orden,o.producto_codigo,o.lote,
       p.orden_id,p.tiempo_ejecucion_nav_min,p.estado,
       (SELECT COUNT_BIG(*) FROM prod.ordenes) AS ProductionOrders,
       (SELECT COUNT_BIG(*) FROM nav.promociones_orden) AS Promotions
FROM nav.ordenes_entrada o
LEFT JOIN prod.ordenes p ON p.empresa_nav_id=o.empresa_nav_id AND p.numero_orden=o.numero_orden
WHERE o.orden_entrada_id=@inboundOrderId;
'@
        [void]$command.Parameters.Add('@inboundOrderId',[Data.SqlDbType]::BigInt)
        $command.Parameters['@inboundOrderId'].Value=$InboundOrderId
        $reader=$command.ExecuteReader();if(-not$reader.Read()){throw 'La orden de entrada no existe.'}
        return [ordered]@{
            OrderNumber=[string]$reader['numero_orden'];ProductNumber=[string]$reader['producto_codigo']
            Lot=[string]$reader['lote'];ProductionOrderId=if($reader['orden_id']-is[DBNull]){$null}else{[long]$reader['orden_id']}
            RunTimeMinutes=if($reader['tiempo_ejecucion_nav_min']-is[DBNull]){$null}else{[decimal]$reader['tiempo_ejecucion_nav_min']}
            State=if($reader['estado']-is[DBNull]){$null}else{[string]$reader['estado']}
            ProductionOrders=[long]$reader['ProductionOrders'];Promotions=[long]$reader['Promotions']
        }
    }
    finally { if($connection.State-ne'Closed'){$connection.Close()};$connection.Dispose() }
}

try {
    $result.Before=Get-PromotionState
    $env:ASPNETCORE_URLS="http://127.0.0.1:$LocalPort"
    $env:ASPNETCORE_ENVIRONMENT='ManualNavPromotion'
    $env:ConnectionStrings__MesDatabase=$connectionString
    $env:Navision__ProductionOrderPromotionEnabled='true'
    $process=Start-Process -FilePath 'C:\Program Files\dotnet\dotnet.exe' `
        -ArgumentList ('"'+$apiDll+'"') -WorkingDirectory $apiDirectory -WindowStyle Hidden `
        -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $healthy=$false
    for($attempt=0;$attempt-lt45;$attempt++){
        if($process.HasExited){throw "La API temporal termino con codigo $($process.ExitCode)."}
        try{$health=Invoke-RestMethod -Uri "http://127.0.0.1:$LocalPort/health/live" -TimeoutSec 2;if($health.status-eq'ok'){$healthy=$true;break}}catch{Start-Sleep -Milliseconds 500}
    }
    if(-not$healthy){throw 'La API temporal no alcanzo el estado saludable.'}
    $payload=@{inboundOrderId=$InboundOrderId;operationNumber=$OperationNumber;correlationId=$CorrelationId}|ConvertTo-Json -Compress
    $endpoint="http://127.0.0.1:$LocalPort/api/admin/production-orders/promote"
    $first=Invoke-RestMethod -Method Post -Uri $endpoint -ContentType 'application/json' -Body $payload -TimeoutSec 120
    $second=Invoke-RestMethod -Method Post -Uri $endpoint -ContentType 'application/json' -Body $payload -TimeoutSec 120
    $result.FirstResponse=[ordered]@{ProductionOrderId=[long]$first.productionOrderId;Outcome=[string]$first.outcome;CorrelationId=[string]$first.correlationId}
    $result.SecondResponse=[ordered]@{ProductionOrderId=[long]$second.productionOrderId;Outcome=[string]$second.outcome;CorrelationId=[string]$second.correlationId}
    $result.After=Get-PromotionState
    if($result.FirstResponse.ProductionOrderId-ne$result.SecondResponse.ProductionOrderId -or
       $result.FirstResponse.Outcome-ne$result.SecondResponse.Outcome -or
       $result.After.ProductionOrderId-ne$result.FirstResponse.ProductionOrderId -or
       $result.After.Promotions-ne($result.Before.Promotions+1)){
        throw 'Las aserciones de promocion manual no se cumplieron.'
    }
    $result.Status='SUCCEEDED'
}
catch{$result.ErrorType=$_.Exception.GetType().FullName;$result.ErrorMessage=$_.Exception.Message}
finally{
    if($null-ne$process-and-not$process.HasExited){Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue;$process.WaitForExit()}
    $result.CompletedUtc=[DateTime]::UtcNow.ToString('O')
    $result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $resolvedResultPath -Encoding UTF8
}
if($result.Status-ne'SUCCEEDED'){exit 1}
