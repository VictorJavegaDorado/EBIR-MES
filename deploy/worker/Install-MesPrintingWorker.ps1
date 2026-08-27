[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ReleasePath,

    [Parameter(Mandatory)]
    [securestring]$MesDatabaseConnectionString,

    [string]$RepositoryRoot = 'C:\MES',
    [string]$ServiceName = 'MES Worker',
    [string]$PrinterCode = 'PRN-VRETTI-01',
    [string]$PrinterQueue = 'MES-VRETTI-420B-PILOT'
)

$ErrorActionPreference = 'Stop'
$created = $false
$eventSourceCreated = $false

function Invoke-Sc {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    & sc.exe @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "sc.exe fallo con codigo $LASTEXITCODE."
    }
}

try {
    $repository = (Resolve-Path -LiteralPath $RepositoryRoot).Path
    $releases = (Resolve-Path -LiteralPath (Join-Path $repository 'runtime\releases')).Path
    $release = (Resolve-Path -LiteralPath $ReleasePath).Path
    if (-not $release.StartsWith($releases + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'La release esta fuera de runtime\releases.'
    }

    $worker = Join-Path $release 'worker\Ebir.Mes.Worker.exe'
    $manifestPath = Join-Path $release 'metadata\manifest.json'
    if (-not (Test-Path -LiteralPath $worker -PathType Leaf) -or
        -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'La release no contiene Worker o manifiesto.'
    }

    $head = (& git -C $repository rev-parse HEAD).Trim()
    $main = (& git -C $repository rev-parse main).Trim()
    $originMain = (& git -C $repository rev-parse origin/main).Trim()
    $changes = @(& git -C $repository status --porcelain)
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($changes.Count -ne 0 -or $head -ne $main -or $head -ne $originMain -or
        $manifest.Commit -ne $head -or $manifest.Branch -ne 'main' -or
        -not $manifest.RepositoryClean -or $manifest.ExternalIntegrationsEnabled) {
        throw 'Repositorio o manifiesto no apto para instalar el servicio.'
    }

    $mismatches = @($manifest.Files | Where-Object {
        $path = Join-Path $release $_.Path.Replace('/', '\')
        -not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-Item -LiteralPath $path).Length -ne $_.Length -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $_.Sha256
    })
    if ($mismatches.Count -ne 0) { throw 'Los hashes de la release no coinciden.' }

    if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
        throw "El servicio '$ServiceName' ya existe."
    }
    if (Get-Process -Name 'Ebir.Mes.Worker' -ErrorAction SilentlyContinue) {
        throw 'Ya existe un proceso Ebir.Mes.Worker.'
    }
    $printer = Get-Printer -Name $PrinterQueue -ErrorAction Stop
    if ($printer.PrinterStatus -ne 'Normal' -or
        @(Get-PrintJob -PrinterName $PrinterQueue -ErrorAction SilentlyContinue).Count -ne 0) {
        throw 'La impresora no esta normal o su cola no esta vacia.'
    }

    $sid = [System.Security.Principal.SecurityIdentifier]'S-1-5-20'
    $account = $sid.Translate([System.Security.Principal.NTAccount]).Value
    if (-not [System.Diagnostics.EventLog]::SourceExists($ServiceName)) {
        New-EventLog -LogName Application -Source $ServiceName
        $eventSourceCreated = $true
    }
    Invoke-Sc create $ServiceName "binPath=" "`"$worker`"" "obj=" $account "start=" delayed-auto "depend=" Spooler
    $created = $true
    Invoke-Sc description $ServiceName 'Worker MES de impresion Windows Spooler en EbirTest'
    Invoke-Sc failure $ServiceName "reset=" 86400 "actions=" restart/60000/restart/60000/none/0

    $plainConnection = [System.Net.NetworkCredential]::new(
        '', $MesDatabaseConnectionString).Password
    try {
        $environment = @(
            'DOTNET_ENVIRONMENT=Production',
            "ConnectionStrings__MesDatabase=$plainConnection",
            'NavisionOutput__Enabled=false',
            'Printing__Enabled=true',
            'Printing__Mode=WindowsSpooler',
            'Printing__RunOnce=false',
            'Printing__PollIntervalMilliseconds=1000',
            'Printing__WindowsSpooler__SubmissionTimeoutSeconds=15',
            "Printing__WindowsSpooler__PrinterQueues__$PrinterCode=$PrinterQueue"
        )
        $serviceKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
        New-ItemProperty -LiteralPath $serviceKey -Name Environment `
            -PropertyType MultiString -Value $environment -Force | Out-Null
    }
    finally {
        $plainConnection = $null
    }

    Start-Service -Name $ServiceName
    $service = Get-Service -Name $ServiceName
    $service.WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
    [pscustomobject]@{
        Installed = $true
        Name = $service.Name
        Status = $service.Status.ToString()
        StartType = $service.StartType.ToString()
        IdentitySid = $sid.Value
        Release = $release
        NavisionOutputEnabled = $false
        PrintingEnabled = $true
        PrintingMode = 'WindowsSpooler'
        PrinterCode = $PrinterCode
        PrinterQueue = $PrinterQueue
    }
}
catch {
    $failure = $_
    if ($created) {
        Stop-Service -Name $ServiceName -ErrorAction SilentlyContinue
        & sc.exe delete $ServiceName | Out-Null
    }
    if ($eventSourceCreated) {
        Remove-EventLog -Source $ServiceName -ErrorAction SilentlyContinue
    }
    throw $failure
}
