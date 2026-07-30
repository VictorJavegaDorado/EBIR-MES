[CmdletBinding()]
param()

$projectRoot = Split-Path -Parent $PSScriptRoot

$requiredPaths = @(
    'AGENTS.md',
    'README.md',
    'Ebir.Mes.sln',
    'global.json',
    'Directory.Build.props',
    'Directory.Packages.props',
    'docs\functional-map.md',
    'src\backend\Ebir.Mes.Api\Ebir.Mes.Api.csproj',
    'src\backend\Ebir.Mes.Application\Ebir.Mes.Application.csproj',
    'src\backend\Ebir.Mes.Domain\Ebir.Mes.Domain.csproj',
    'src\backend\Ebir.Mes.Infrastructure\Ebir.Mes.Infrastructure.csproj',
    'src\backend\Ebir.Mes.Integrations\Ebir.Mes.Integrations.csproj',
    'src\backend\Ebir.Mes.Worker\Ebir.Mes.Worker.csproj',
    'src\frontend\package.json',
    'src\frontend\src\features\line-identification\ui\LineIdentificationPage.tsx',
    'tests\backend\Ebir.Mes.Domain.Tests\Ebir.Mes.Domain.Tests.csproj',
    'tests\backend\Ebir.Mes.Application.Tests\Ebir.Mes.Application.Tests.csproj',
    'tests\backend\Ebir.Mes.IntegrationTests\Ebir.Mes.IntegrationTests.csproj',
    'tests\backend\Ebir.Mes.ArchitectureTests\Ebir.Mes.ArchitectureTests.csproj',
    'database\README.md',
    'legacy-reference\README.md'
)

$missingPaths = $requiredPaths |
    Where-Object { -not (Test-Path -LiteralPath (Join-Path $projectRoot $_)) }

if ($missingPaths.Count -gt 0) {
    $missingPaths | ForEach-Object { Write-Error "Falta: $_" }
    exit 1
}

$projectFiles = Get-ChildItem -LiteralPath $projectRoot -Recurse -Filter '*.csproj'
foreach ($projectFile in $projectFiles) {
    try {
        [void][xml](Get-Content -LiteralPath $projectFile.FullName -Raw)
    }
    catch {
        Write-Error "XML de proyecto no válido: $($projectFile.FullName)"
        exit 1
    }
}

Write-Host "Estructura válida: $($requiredPaths.Count) rutas requeridas y $($projectFiles.Count) proyectos .NET."
