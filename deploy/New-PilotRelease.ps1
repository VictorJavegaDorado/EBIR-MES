[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9A-Za-z][0-9A-Za-z._-]*$')]
    [string]$ReleaseId,

    [string]$RepositoryRoot = 'C:\MES',

    [switch]$AllowDirty
)

$ErrorActionPreference = 'Stop'

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Command,

        [Parameter(Mandatory)]
        [string]$FailureMessage
    )

    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$FailureMessage Exit code: $LASTEXITCODE."
    }
}

$repository = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$runtimeRoot = Join-Path $repository 'runtime'
$releasesRoot = Join-Path $runtimeRoot 'releases'
$temporaryRoot = Join-Path $runtimeRoot 'shared\temp'
$destination = Join-Path $releasesRoot $ReleaseId

foreach ($requiredRoot in @($runtimeRoot, $releasesRoot, $temporaryRoot)) {
    if (-not (Test-Path -LiteralPath $requiredRoot -PathType Container)) {
        throw "Required runtime directory not found: $requiredRoot"
    }
}

$lockPath = Join-Path $temporaryRoot "pilot-release-$ReleaseId.lock"
try {
    $releaseLock = [System.IO.File]::Open(
        $lockPath,
        [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )
}
catch {
    throw "Another release build is already using ReleaseId '$ReleaseId'."
}

try {
    if (Test-Path -LiteralPath $destination) {
        throw "Release already exists and will not be overwritten: $destination"
    }

    $head = (& git -C $repository rev-parse HEAD).Trim()
    $branch = (& git -C $repository branch --show-current).Trim()
    $changes = @(& git -C $repository status --porcelain)

    if ($changes.Count -gt 0 -and -not $AllowDirty) {
        throw 'The repository is not clean. Use -AllowDirty only for a pre-commit validation candidate.'
    }

    $workingDirectory = Join-Path (
        (Resolve-Path -LiteralPath $temporaryRoot).Path
    ) "pilot-release-$([guid]::NewGuid().ToString('N'))"

    if (-not $workingDirectory.StartsWith(
        (Resolve-Path -LiteralPath $temporaryRoot).Path,
        [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Calculated working directory is outside runtime\shared\temp.'
    }

    $frontendRoot = Join-Path $repository 'src\frontend'
    $apiProject = Join-Path $repository 'src\backend\Ebir.Mes.Api\Ebir.Mes.Api.csproj'
    $workerProject = Join-Path $repository 'src\backend\Ebir.Mes.Worker\Ebir.Mes.Worker.csproj'
    $apiOutput = Join-Path $workingDirectory 'api'
    $workerOutput = Join-Path $workingDirectory 'worker'

    New-Item -ItemType Directory -Path $workingDirectory | Out-Null

    try {
    Invoke-NativeCommand {
        npm --prefix $frontendRoot run build
    } 'Frontend build failed.'

    Invoke-NativeCommand {
        dotnet publish $apiProject --configuration Release --no-restore --output $apiOutput
    } 'API publish failed.'

    Invoke-NativeCommand {
        dotnet publish $workerProject --configuration Release --no-restore --output $workerOutput
    } 'Worker publish failed.'

    $requiredFiles = @(
        (Join-Path $apiOutput 'Ebir.Mes.Api.dll'),
        (Join-Path $apiOutput 'web.config'),
        (Join-Path $apiOutput 'wwwroot\index.html'),
        (Join-Path $workerOutput 'Ebir.Mes.Worker.dll')
    )

    foreach ($requiredFile in $requiredFiles) {
        if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
            throw "Required release artifact not found: $requiredFile"
        }
    }

    $frontendAssets = @(
        Get-ChildItem -LiteralPath (Join-Path $apiOutput 'wwwroot\assets') `
            -File -ErrorAction SilentlyContinue
    )
    if ($frontendAssets.Count -eq 0) {
        throw 'The combined API publish does not contain frontend assets.'
    }

    $publishedSettings = Get-Content -LiteralPath (
        Join-Path $apiOutput 'appsettings.json'
    ) -Raw | ConvertFrom-Json
    if ($publishedSettings.ConnectionStrings.MesDatabase) {
        throw 'The published appsettings.json contains a database connection string.'
    }

    $artifactFiles = @(
        Get-ChildItem -LiteralPath $workingDirectory -Recurse -File |
            Sort-Object FullName
    )
    $hashes = @(
        $artifactFiles | ForEach-Object {
            $fileHash = (
                Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
            ).Hash.ToLowerInvariant()

            [pscustomobject][ordered]@{
                Path = $_.FullName.Substring(
                    $workingDirectory.Length + 1
                ).Replace('\', '/')
                Sha256 = $fileHash
                Length = $_.Length
            }
        }
    )

    $metadataDirectory = Join-Path $workingDirectory 'metadata'
    New-Item -ItemType Directory -Path $metadataDirectory | Out-Null

    $manifest = [ordered]@{
        ReleaseId = $ReleaseId
        Commit = $head
        Branch = $branch
        RepositoryClean = ($changes.Count -eq 0)
        Changes = $changes
        BuiltUtc = [DateTime]::UtcNow.ToString('o')
        Database = 'EBIR_MES_TEST'
        ExternalIntegrationsEnabled = $false
        HostingMode = 'ApiWithSpa'
        ApiFiles = @(Get-ChildItem -LiteralPath $apiOutput -Recurse -File).Count
        WorkerFiles = @(Get-ChildItem -LiteralPath $workerOutput -Recurse -File).Count
        FrontendFiles = @(
            Get-ChildItem -LiteralPath (Join-Path $apiOutput 'wwwroot') `
                -Recurse -File
        ).Count
        Files = $hashes
    }

    $manifest | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath (
            Join-Path $metadataDirectory 'manifest.json'
        ) -Encoding UTF8
    $hashes | Export-Csv -LiteralPath (
        Join-Path $metadataDirectory 'sha256.csv'
    ) -NoTypeInformation -Encoding UTF8

    Move-Item -LiteralPath $workingDirectory -Destination $destination

    [pscustomobject]@{
        ReleaseId = $ReleaseId
        Path = $destination
        Commit = $head
        RepositoryClean = ($changes.Count -eq 0)
        HostingMode = 'ApiWithSpa'
        ApiFiles = $manifest.ApiFiles
        WorkerFiles = $manifest.WorkerFiles
        FrontendFiles = $manifest.FrontendFiles
    }
    }
    catch {
        if (Test-Path -LiteralPath $workingDirectory) {
            Remove-Item -LiteralPath $workingDirectory -Recurse -Force
        }
        throw
    }
}
finally {
    $releaseLock.Dispose()
}
