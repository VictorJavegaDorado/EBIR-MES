$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$packagePath = Join-Path $repositoryRoot 'database\014A_cerrar_palet_idempotente.sql'
$sql = [System.IO.File]::ReadAllText($packagePath)

$requiredFragments = @(
    "IF DB_NAME() <> N'EBIR_MES_TEST'",
    "OBJECT_ID(N'prod.cerrar_palet', N'P')",
    "DATABASE_PRINCIPAL_ID(N'mes_runtime') IS NULL",
    'EXEC sys.sp_executesql @definicion',
    'CREATE OR ALTER PROCEDURE prod.cerrar_palet_idempotente',
    'SET XACT_ABORT ON',
    'BEGIN TRANSACTION',
    'sp_getapplock',
    'MES:CORRELACION:',
    'FROM aud.eventos WITH (UPDLOCK, HOLDLOCK)',
    'FROM prod.palets p WITH (UPDLOCK, HOLDLOCK)',
    'FROM nav.operaciones n WITH (UPDLOCK, HOLDLOCK)',
    'FROM imp.etiquetas e WITH (UPDLOCK, HOLDLOCK)',
    'EXEC prod.cerrar_palet',
    'ROLLBACK TRANSACTION',
    'THROW 55400',
    'THROW 55401',
    'THROW 55402',
    'THROW 55403',
    'THROW 55404',
    'THROW;',
    'REVOKE EXECUTE ON OBJECT::prod.cerrar_palet FROM mes_runtime',
    'GRANT EXECUTE ON OBJECT::prod.cerrar_palet_idempotente TO mes_runtime',
    'FROM sys.database_permissions',
    'COMMIT TRANSACTION'
)

foreach ($fragment in $requiredFragments) {
    if (-not $sql.Contains($fragment)) {
        throw "Falta el fragmento requerido en 014A: $fragment"
    }
}

if (($sql | Select-String -Pattern '(?im)^\s*USE\s+' -AllMatches).Matches.Count -ne 0) {
    throw '014A no puede contener USE.'
}

if (($sql | Select-String -Pattern '(?i)\b(?:FROM|JOIN|UPDATE|INSERT\s+INTO|EXEC)\s+\[[^\]]+\]\.\[[^\]]+\]\.\[' -AllMatches).Matches.Count -ne 0) {
    throw '014A no puede contener referencias de tres partes.'
}

if (($sql | Select-String -Pattern '(?im)^\s*CREATE OR ALTER PROCEDURE\s+' -AllMatches).Matches.Count -ne 1) {
    throw '014A debe definir exactamente un procedimiento.'
}

if (($sql | Select-String -Pattern '(?im)^\s*BEGIN TRANSACTION\s*;?\s*$' -AllMatches).Matches.Count -ne 2) {
    throw '014A debe abrir una transacción de instalación y una de negocio.'
}

if (($sql | Select-String -Pattern '(?im)^\s*COMMIT TRANSACTION\s*;?\s*$' -AllMatches).Matches.Count -ne 3) {
    throw '014A debe confirmar el reintento, el primer cierre o la instalación.'
}

Write-Host 'Revisión estática 014 correcta.'

$testFiles = @(
    '00_PREVUELO_Y_FIXTURES_014.sql',
    '01_FUNCIONALES_014.sql',
    '05_CONCURRENCIA_A_014.sql',
    '06_CONCURRENCIA_B_014.sql',
    '07_PERMISOS_014.sql',
    '99A_LIMPIEZA_014.sql',
    '99B_DBCC_014.sql'
)

foreach ($testFile in $testFiles) {
    $testPath = Join-Path $PSScriptRoot $testFile
    if (-not (Test-Path -LiteralPath $testPath)) {
        throw "Falta la fase de prueba 014: $testFile"
    }

    $testSql = [System.IO.File]::ReadAllText($testPath)
    if (-not $testSql.Contains("DB_NAME() <> N'EBIR_MES_TEST'")) {
        throw "$testFile no limita el destino a EBIR_MES_TEST."
    }
    if (($testSql | Select-String -Pattern '(?im)^\s*USE\s+' -AllMatches).Matches.Count -ne 0) {
        throw "$testFile no puede contener USE."
    }
    if ($testSql -match '(?i)\b(?:sqlcmd|invoke-sqlcmd|https?://|rfid|\\\\)') {
        throw "$testFile contiene una posible llamada o destino externo."
    }
}

$functionalPath = Join-Path $PSScriptRoot '01_FUNCIONALES_014.sql'
$functionalSql = [System.IO.File]::ReadAllText($functionalPath)
foreach ($errorNumber in '55400', '55402', '55403', '51400') {
    if (-not $functionalSql.Contains("ERROR_NUMBER() <> $errorNumber")) {
        throw "La fase funcional no verifica el error $errorNumber."
    }
}

foreach ($fragment in @('empleado_id, entidad', "N'ZZTEST_OTRA_OPERACION', @op", '55403 dejo filas parciales', '@@TRANCOUNT')) {
    if (-not $functionalSql.Contains($fragment)) {
        throw "La fase funcional no protege el contrato 55403: $fragment"
    }
}

$clientA = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '05_CONCURRENCIA_A_014.sql'))
$clientB = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '06_CONCURRENCIA_B_014.sql'))
foreach ($fragment in @("codigo_nav = N'ZZ14-OP1'", "'14050100-0000-0000-0000-000000000001'", 'BARRERA_IDENTICA', '@@TRANCOUNT')) {
    if (-not $clientA.Contains($fragment) -or -not $clientB.Contains($fragment)) {
        throw "Los clientes no mantienen el contrato de carrera identica: $fragment"
    }
}
foreach ($fragment in @('BEGIN TRANSACTION', "WAITFOR DELAY '00:00:05'")) {
    if (-not $clientA.Contains($fragment)) {
        throw "El cliente A no conserva bloqueos para forzar contencion: $fragment"
    }
}
foreach ($fragment in @('DATEDIFF(MILLISECOND', 'no demostro contencion')) {
    if (-not $clientB.Contains($fragment)) {
        throw "El cliente B no demuestra la espera concurrente: $fragment"
    }
}
if (-not $clientB.Contains('@error <> 51403') -or -not $clientB.Contains('BARRERA_DISTINTA')) {
    throw 'La carrera de correlaciones distintas no verifica ganador y rechazo 51403.'
}

$permissionsPath = Join-Path $PSScriptRoot '07_PERMISOS_014.sql'
$permissionsSql = [System.IO.File]::ReadAllText($permissionsPath)
if (-not $permissionsSql.Contains("prod.cerrar_palet_idempotente") -or
    -not $permissionsSql.Contains("prod.cerrar_palet")) {
    throw 'La fase de permisos no comprueba el traslado de contrato.'
}

$cleanupSql = [System.IO.File]::ReadAllText(
    (Join-Path $PSScriptRoot '99A_LIMPIEZA_014.sql'))
$dbccSql = [System.IO.File]::ReadAllText(
    (Join-Path $PSScriptRoot '99B_DBCC_014.sql'))
if ($cleanupSql.Contains('DBCC CHECKDB')) {
    throw 'La limpieza no puede ejecutar DBCC.'
}
if (-not $dbccSql.Contains("DBCC CHECKDB (N'EBIR_MES_TEST')")) {
    throw 'La fase de integridad no contiene DBCC CHECKDB.'
}
if ($dbccSql -match '(?im)^\s*(?:INSERT|UPDATE|DELETE|MERGE)\s+') {
    throw 'La fase DBCC no puede modificar datos.'
}

Write-Host 'Revisión estática de pruebas 014 correcta.'
