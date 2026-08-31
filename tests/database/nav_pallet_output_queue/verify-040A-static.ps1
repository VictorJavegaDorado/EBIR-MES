$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$scriptPath = Join-Path $root 'database\040A_retirar_cierre_fl_42_obsoleto.sql'
$sql = Get-Content -LiteralPath $scriptPath -Raw

$required = @(
    "IF DB_NAME() <> N'EBIR_MES_TEST'",
    'BEGIN TRANSACTION',
    'BEGIN CATCH',
    'ROLLBACK TRANSACTION',
    'operacion_nav_id=42',
    "clave_idempotencia=N'MES:CIERRE_FL:31'",
    "tipo=N'CIERRE_FL' AND orden_id=31",
    "estado=N'PENDIENTE' AND numero_intentos=0",
    'identificador_externo IS NULL',
    "JSON_VALUE(payload,'$.numero_orden')=N'FL26-00004'",
    'operacion_nav_id=39',
    "clave_idempotencia=N'MES:CIERRE_FL:30'",
    's.sesion_linea_id=35',
    "s.estado=N'SIN_OPERARIOS'",
    'o.cantidad_objetivo=100 AND o.cantidad_buena_acumulada=100',
    'o.cantidad_reservada_activa=0',
    "SET estado=N'ANULADA'",
    'CIERRE_FL_SUPERSEDED_BY_LOCAL_COMPLETION',
    "SET estado=N'PENDIENTE_CIERRE'",
    "SET estado=N'SIN_OPERARIOS'",
    "N'CIERRE_FL_OBSOLETO_ANULADO'",
    'WITH (UPDLOCK,HOLDLOCK)',
    'navWriteOperations',
    'trabajo_impresion_id=23 AND etiqueta_id=33',
    "estado=N'COMPLETADO' AND es_reimpresion=0"
)

foreach ($token in $required) {
    if (-not $sql.Contains($token)) {
        throw "Falta el contrato estatico requerido: $token"
    }
}

if ($sql -match '(?im)^\s*USE\s+' -or
    $sql -match '(?i)\b(?!EBIR_MES_TEST\b)[A-Za-z0-9_]+\.(?:nav|prod|imp|cfg|seg|aud)\.') {
    throw 'El paquete contiene una referencia de base no permitida.'
}

if ($sql -match '(?i)\b(?:TRUNCATE|DROP|DELETE|MERGE)\b') {
    throw 'El paquete 040A contiene una operacion destructiva no permitida.'
}

if ($sql -match '(?i)RegistrarSalidaFabricacion|OpenClosePalletMES|https?://|OPENROWSET|OPENDATASOURCE|sp_OA|xp_cmdshell') {
    throw 'El paquete 040A contiene una via de contacto externo no permitida.'
}

if (($sql | Select-String -Pattern '(?im)^\s*UPDATE\s+nav\.operaciones\s*$' -AllMatches).Matches.Count -ne 1 -or
    ($sql | Select-String -Pattern '(?im)^\s*UPDATE\s+prod\.ordenes\s*$' -AllMatches).Matches.Count -ne 1 -or
    ($sql | Select-String -Pattern '(?im)^\s*UPDATE\s+prod\.estados_linea\s*$' -AllMatches).Matches.Count -ne 1) {
    throw 'El paquete debe contener exactamente sus tres actualizaciones autorizadas.'
}

if ($sql -match '(?im)^\s*(?:UPDATE|INSERT)\s+(?:imp\.|prod\.palets|prod\.sesiones_linea|nav\.intentos_operacion)') {
    throw 'El paquete no puede modificar impresion, palets, sesion ni intentos NAV.'
}

[pscustomobject]@{
    Package = '040A'
    DatabaseGuard = $true
    Transactional = $true
    NavContact = $false
    Printing = $false
    ExactCloseOperation = 42
    LegacyOperationUntouched = 39
    ExactOrder = 31
    ExactSession = 35
    TargetOrderState = 'PENDIENTE_CIERRE'
    TargetLineState = 'SIN_OPERARIOS'
    Audited = $true
}
