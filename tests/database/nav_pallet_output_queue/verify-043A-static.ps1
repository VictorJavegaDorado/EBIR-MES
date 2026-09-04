$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$scriptPath = Join-Path $root 'database\043A_confirmar_reconciliacion_tardia_salida_palet_49.sql'
$sql = Get-Content -LiteralPath $scriptPath -Raw

$required = @(
    "IF DB_NAME() <> N'EBIR_MES_TEST'",
    'BEGIN TRANSACTION',
    'BEGIN CATCH',
    'ROLLBACK TRANSACTION',
    'operacion_nav_id=49',
    "n.estado=N'RESULTADO_DESCONOCIDO' AND n.numero_intentos=12",
    "n.identificador_externo=N'26853'",
    "o.orden_id=35 AND o.numero_orden=N'FL26-00007'",
    "o.producto_codigo=N'27920LG'",
    'o.cantidad_objetivo=20 AND o.cantidad_buena_acumulada=20',
    'o.cantidad_reservada_activa=0',
    'p.palet_id=38 AND p.numero_palet=1 AND p.cantidad_buena=20',
    'p.es_ultimo=1 AND p.autorizado_por_supervisor_id=48',
    'numero_intento=12',
    "JSON_VALUE(respuesta,'$.reason')=N'OutputStateNotRegistered'",
    'etiqueta_id=40 AND orden_id=35 AND palet_id=38',
    "tipo=N'PALET' AND estado=N'PENDIENTE_NAV'",
    'EXEC nav.confirmar_salida_palet',
    '@operacion_nav_id=49',
    '@identificador_externo=N''26853''',
    'SUPERVISED_EXISTING_OUTPUT',
    "estado=N'CONFIRMADA'",
    'numero_intentos=13',
    "tipo=N'PALET' AND estado=N'LISTA'",
    "es_reimpresion=0 AND estado=N'PENDIENTE'",
    'WITH (UPDLOCK,HOLDLOCK)'
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
    throw 'El paquete 043A no puede eliminar ni fusionar datos u objetos.'
}

if ($sql -match '(?i)RegistrarSalidaFabricacion|https?://|OPENROWSET|OPENDATASOURCE|sp_OA|xp_cmdshell') {
    throw 'El paquete 043A contiene una via de contacto externo no permitida.'
}

if ($sql -match '(?im)^\s*UPDATE\s+nav\.operaciones' -or
    $sql -match '(?im)^\s*(?:UPDATE|INSERT|MERGE)\s+(?:imp\.|prod\.|nav\.intentos_operacion\b)') {
    throw '043A solo puede mutar mediante los procedimientos operativos publicados.'
}

if (($sql | Select-String -Pattern '(?i)EXEC nav\.confirmar_salida_palet' -AllMatches).Matches.Count -ne 1) {
    throw '043A debe confirmar exactamente una vez la operacion protegida.'
}

[pscustomobject]@{
    Package = '043A'
    DatabaseGuard = $true
    Transactional = $true
    NavContact = $false
    ExactOperation = 49
    ExactOrder = 35
    ExactPallet = 38
    ExactLabel = 40
    ExternalIdentifier = 26853
    SupervisedReconciliation = $true
    OriginalPrintJob = 1
    ConfirmationProcedure = 'nav.confirmar_salida_palet'
}
