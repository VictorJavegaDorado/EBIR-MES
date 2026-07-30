$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$packagePath = Join-Path $repositoryRoot 'database\014A_cerrar_palet_idempotente.sql'
$sql = [System.IO.File]::ReadAllText($packagePath)

$requiredFragments = @(
    "IF DB_NAME() <> N'EBIR_MES_TEST'",
    'CREATE OR ALTER PROCEDURE prod.cerrar_palet_idempotente',
    'SET XACT_ABORT ON',
    'BEGIN TRANSACTION',
    'sp_getapplock',
    "N'MES:CORRELACION:'",
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
    'REVOKE EXECUTE ON OBJECT::prod.cerrar_palet FROM mes_runtime',
    'GRANT EXECUTE ON OBJECT::prod.cerrar_palet_idempotente TO mes_runtime'
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

if (($sql | Select-String -Pattern '(?im)^\s*BEGIN TRANSACTION\s*;?\s*$' -AllMatches).Matches.Count -ne 1) {
    throw '014A debe abrir exactamente una transacción de negocio.'
}

if (($sql | Select-String -Pattern '(?im)^\s*COMMIT TRANSACTION\s*;?\s*$' -AllMatches).Matches.Count -ne 2) {
    throw '014A debe confirmar únicamente el reintento o el primer cierre.'
}

Write-Host 'Revisión estática 014 correcta.'
