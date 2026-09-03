[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ReleasePath,

    [Parameter(Mandatory)]
    [securestring]$MesDatabaseConnectionString,

    [string]$RepositoryRoot = 'C:\MES',
    [string]$ServiceName = 'MES NAV Worker',
    [string]$PrintingServiceName = 'MES Worker',
    [string]$LineCode = 'LINEA-TEST-01',
    [string]$AssemblyLine = 'L01'
)

$ErrorActionPreference = 'Stop'
$created = $false
$eventSourceCreated = $false
$allowedEndpoint =
    'http://NAVISION2.EBIR.LOCAL:7147/EbirTest/WS/EBIR/Codeunit/WS_CPP_ControlPlanta'

function Invoke-Sc {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    & sc.exe @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "sc.exe fallo con codigo $LASTEXITCODE."
    }
}

try {
    if ($ServiceName -ne 'MES NAV Worker' -or $PrintingServiceName -ne 'MES Worker') {
        throw 'Los nombres de servicio deben coincidir con el contrato de EbirTest.'
    }
    if ($LineCode -ne 'LINEA-TEST-01' -or $AssemblyLine -ne 'L01') {
        throw 'El mapeo de linea debe coincidir con el piloto de EbirTest.'
    }

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
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            $_.Sha256
    })
    if ($mismatches.Count -ne 0) { throw 'Los hashes de la release no coinciden.' }

    if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
        throw "El servicio '$ServiceName' ya existe."
    }
    $printingService = Get-Service -Name $PrintingServiceName -ErrorAction Stop
    if ($printingService.Status -ne 'Running') {
        throw 'El Worker de impresion debe permanecer iniciado y separado.'
    }
    $printingServiceKey =
        "HKLM:\SYSTEM\CurrentControlSet\Services\$PrintingServiceName"
    $printingEnvironment = @((Get-ItemProperty `
        -LiteralPath $printingServiceKey `
        -Name Environment `
        -ErrorAction Stop).Environment)
    if ($printingEnvironment -notcontains 'NavisionOutput__Enabled=false' -or
        $printingEnvironment -notcontains 'Printing__Enabled=true' -or
        $printingEnvironment -notcontains 'Printing__RunOnce=false') {
        throw 'El servicio de impresion no conserva el perfil continuo aislado.'
    }

    $plainConnection = [System.Net.NetworkCredential]::new(
        '', $MesDatabaseConnectionString).Password
    try {
        $connectionOptions = [System.Data.SqlClient.SqlConnectionStringBuilder]::new(
            $plainConnection)
        if (-not $connectionOptions.IntegratedSecurity -or
            $connectionOptions.InitialCatalog -ne 'EBIR_MES_TEST' -or
            $connectionOptions.DataSource -ne 'SQL.EBIR.LOCAL\NAVISION2017') {
            throw 'La conexion debe usar autenticacion integrada y EBIR_MES_TEST exacta.'
        }
        $connection = [System.Data.SqlClient.SqlConnection]::new($plainConnection)
        try {
            $connection.Open()
            $command = $connection.CreateCommand()
            $command.CommandTimeout = 30
            $command.CommandText = @'
SET NOCOUNT ON;
IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Base no autorizada.', 1;
IF OBJECT_DEFINITION(OBJECT_ID(N'nav.reservar_siguiente_salida_palet'))
       NOT LIKE N'%numero_intentos < 12%'
 OR OBJECT_DEFINITION(OBJECT_ID(N'nav.fallar_salida_palet'))
       NOT LIKE N'%DISCOVER_AFTER_BASELINE%'
    THROW 51073, 'El contrato 041A no esta instalado.', 1;
IF EXISTS
(
    SELECT 1 FROM nav.operaciones
    WHERE tipo=N'SALIDA_PALET'
      AND estado IN
          (N'PENDIENTE',N'PROCESANDO',N'ERROR_REINTENTABLE',N'RESULTADO_DESCONOCIDO')
)
    THROW 51076, 'Existen salidas NAV no terminales antes de instalar el servicio.', 1;
'@
            $command.ExecuteNonQuery() | Out-Null
        }
        finally {
            $connection.Dispose()
        }

        $sid = [System.Security.Principal.SecurityIdentifier]'S-1-5-20'
        $account = $sid.Translate([System.Security.Principal.NTAccount]).Value
        if (-not [System.Diagnostics.EventLog]::SourceExists($ServiceName)) {
            New-EventLog -LogName Application -Source $ServiceName
            $eventSourceCreated = $true
        }
        Invoke-Sc create $ServiceName "binPath=" "`"$worker`"" "obj=" $account `
            "start=" delayed-auto "depend=" LanmanWorkstation
        $created = $true
        Invoke-Sc description $ServiceName `
            'Worker MES de salidas NAV exclusivo de EbirTest'
        Invoke-Sc failure $ServiceName "reset=" 86400 `
            "actions=" restart/60000/restart/60000/none/0

        $environment = @(
            'DOTNET_ENVIRONMENT=Production',
            "ConnectionStrings__MesDatabase=$plainConnection",
            "Worker__ServiceName=$ServiceName",
            'NavisionOutput__Enabled=true',
            'NavisionOutput__RunOnce=false',
            'NavisionOutput__PollIntervalMilliseconds=1000',
            'NavisionOutput__RequestTimeoutSeconds=10',
            "NavisionOutput__ServiceEndpoint=$allowedEndpoint",
            "NavisionOutput__AssemblyLineMappings__$LineCode=$AssemblyLine",
            'Printing__Enabled=false',
            'Printing__Mode=Disabled'
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
        NavisionOutputEnabled = $true
        PrintingEnabled = $false
        EndpointEnvironment = 'EbirTest'
        Company = 'EBIR'
        LineCode = $LineCode
        AssemblyLine = $AssemblyLine
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
