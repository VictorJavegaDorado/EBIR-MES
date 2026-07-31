[CmdletBinding()]
param(
    [string]$RepositoryRoot = 'C:\MES',
    [string]$SiteName = 'MES',
    [string]$ExpectedCommit
)

$ErrorActionPreference = 'Stop'
Import-Module WebAdministration

$head = (& git -C $RepositoryRoot rev-parse HEAD).Trim()
$originMain = (& git -C $RepositoryRoot rev-parse origin/main).Trim()
$status = @(& git -C $RepositoryRoot status --porcelain)

if ($ExpectedCommit -and $head -ne $ExpectedCommit) {
    throw "HEAD '$head' does not match expected commit '$ExpectedCommit'."
}

$site = Get-Website -Name $SiteName
$pool = Get-Item "IIS:\AppPools\$($site.ApplicationPool)"
$bindings = @(
    Get-WebBinding -Name $SiteName | ForEach-Object {
        $certificate = $null
        if ($_.certificateHash) {
            $thumbprint = if ($_.certificateHash -is [byte[]]) {
                ([BitConverter]::ToString($_.certificateHash)).Replace('-', '')
            } else {
                [string]$_.certificateHash
            }
            $certificate = Get-Item "Cert:\LocalMachine\My\$thumbprint" -ErrorAction SilentlyContinue
        }

        [ordered]@{
            protocol = $_.protocol
            bindingInformation = $_.bindingInformation
            certificateThumbprint = $certificate.Thumbprint
            certificateSubject = $certificate.Subject
            certificateNotAfter = $certificate.NotAfter
        }
    }
)

$currentPath = Join-Path $RepositoryRoot 'runtime\current'
$releasesPath = Join-Path $RepositoryRoot 'runtime\releases'
$currentItem = Get-Item -LiteralPath $currentPath -Force -ErrorAction SilentlyContinue
$releases = @(
    Get-ChildItem -LiteralPath $releasesPath -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        ForEach-Object {
            $standaloneFrontend =
                Test-Path (Join-Path $_.FullName 'frontend\index.html')
            $combinedFrontend =
                Test-Path (Join-Path $_.FullName 'api\wwwroot\index.html')
            $apiExists =
                Test-Path (Join-Path $_.FullName 'api\Ebir.Mes.Api.dll')
            $workerExists =
                Test-Path (Join-Path $_.FullName 'worker\Ebir.Mes.Worker.dll')
            $manifestExists =
                Test-Path (Join-Path $_.FullName 'metadata\manifest.json')
            $hashListPath = Join-Path $_.FullName 'metadata\sha256.csv'
            $hashListExists = Test-Path $hashListPath -PathType Leaf
            $hashListSchemaValid = $false
            if ($hashListExists) {
                try {
                    $firstHash = Import-Csv -LiteralPath $hashListPath |
                        Select-Object -First 1
                    $hashProperties = @(
                        $firstHash.PSObject.Properties.Name
                    )
                    $hashListSchemaValid =
                        $hashProperties -contains 'Path' -and
                        $hashProperties -contains 'Sha256' -and
                        $hashProperties -contains 'Length'
                }
                catch {
                    $hashListSchemaValid = $false
                }
            }
            $allowedTopDirectories = @(
                'api',
                'frontend',
                'metadata',
                'worker'
            )
            $unexpectedTopDirectories = @(
                Get-ChildItem -LiteralPath $_.FullName -Directory |
                    Where-Object Name -NotIn $allowedTopDirectories |
                    Select-Object -ExpandProperty Name
            )

            [ordered]@{
                id = $_.Name
                api = $apiExists
                worker = $workerExists
                frontend = $standaloneFrontend
                combinedFrontend = $combinedFrontend
                hostingMode = if ($combinedFrontend) {
                    'ApiWithSpa'
                } elseif ($standaloneFrontend) {
                    'Separated'
                } else {
                    'Missing'
                }
                manifest = $manifestExists
                hashList = $hashListExists
                hashListSchemaValid = $hashListSchemaValid
                unexpectedTopDirectories = $unexpectedTopDirectories
                packageStructureValid =
                    $apiExists -and
                    $workerExists -and
                    ($combinedFrontend -or $standaloneFrontend) -and
                    $manifestExists -and
                    $hashListSchemaValid -and
                    $unexpectedTopDirectories.Count -eq 0
            }
        }
)

$workerService = Get-Service -Name 'MES Worker' -ErrorAction SilentlyContinue
$ancm = Get-WebGlobalModule |
    Where-Object Name -eq 'AspNetCoreModuleV2' |
    Select-Object -First 1

[ordered]@{
    checkedAt = (Get-Date).ToString('o')
    repository = [ordered]@{
        path = $RepositoryRoot
        head = $head
        originMain = $originMain
        clean = ($status.Count -eq 0)
        changes = $status
    }
    iis = [ordered]@{
        site = $site.Name
        state = $site.State
        physicalPath = $site.PhysicalPath
        applicationPool = $site.ApplicationPool
        poolState = $pool.state
        poolIdentity = $pool.processModel.identityType
        aspNetCoreModuleV2 = [bool]$ancm
        bindings = $bindings
    }
    runtime = [ordered]@{
        currentExists = [bool]$currentItem
        currentLinkType = $currentItem.LinkType
        currentTarget = $currentItem.Target
        releases = $releases
    }
    worker = if ($workerService) {
        [ordered]@{
            installed = $true
            status = $workerService.Status.ToString()
            startType = $workerService.StartType.ToString()
        }
    } else {
        [ordered]@{ installed = $false }
    }
} | ConvertTo-Json -Depth 8
