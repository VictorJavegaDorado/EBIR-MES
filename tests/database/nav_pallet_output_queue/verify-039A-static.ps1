$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$scriptPath = Join-Path $root 'database\039A_recuperar_salida_palet_41_identificador.sql'
$sql = Get-Content -LiteralPath $scriptPath -Raw

$required = @(
    "IF DB_NAME() <> N'EBIR_MES_TEST'",
    'BEGIN TRANSACTION',
    'BEGIN CATCH',
    'ROLLBACK TRANSACTION',
    'operacion_nav_id=41',
    "n.estado=N'RESULTADO_DESCONOCIDO' AND n.numero_intentos=1",
    'n.identificador_externo IS NULL',
    'n.reservado_utc IS NULL AND n.reservado_por IS NULL',
    'o.orden_id=31',
    "o.numero_orden=N'FL26-00004'",
    "o.estado=N'PENDIENTE_CIERRE'",
    'o.cantidad_objetivo=100 AND o.cantidad_buena_acumulada=100',
    'o.cantidad_reservada_activa=0',
    'p.palet_id=31',
    'p.numero_palet=5',
    'p.cantidad_buena=20',
    'p.es_ultimo=1',
    'p.autorizado_por_supervisor_id=48',
    'numero_intento=1',
    "resultado=N'RESULTADO_DESCONOCIDO' AND codigo_http=200",
    "JSON_VALUE(respuesta,'$.adapter')=N'NavisionSoapPalletOutputSender'",
    "JSON_VALUE(respuesta,'$.outcome')=N'UnknownResult'",
    "JSON_VALUE(respuesta,'$.reason')=N'CodeunitReturnedFalse'",
    "JSON_VALUE(respuesta,'$.baselineMaximumId'))=26845",
    'etiqueta_id=33 AND orden_id=31 AND palet_id=31',
    "tipo=N'PALET' AND estado=N'PENDIENTE_NAV'",
    'FROM imp.trabajos_impresion WHERE etiqueta_id=33',
    "SET identificador_externo=N'26846'",
    "N'NAV_SALIDA_IDENTIFICADOR_RECUPERADO'",
    'WITH (UPDLOCK,HOLDLOCK)',
    'proximo_intento_utc=SYSUTCDATETIME()',
    'procesada_utc=NULL,reservado_utc=NULL,reservado_por=NULL'
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

if ($sql -match '(?i)\b(?:TRUNCATE|DROP|DELETE)\b') {
    throw 'El paquete 039A no puede eliminar objetos ni datos.'
}

if ($sql -match '(?i)RegistrarSalidaFabricacion|https?://|OPENROWSET|OPENDATASOURCE|sp_OA|xp_cmdshell') {
    throw 'El paquete 039A contiene una via de contacto externo no permitida.'
}

if ($sql -notmatch '(?is)(?:IF|OR)\s+EXISTS\s*\(\s*SELECT 1 FROM imp\.trabajos_impresion(?: WITH \(UPDLOCK,HOLDLOCK\))?\s+WHERE etiqueta_id=33\s*\)') {
    throw 'El paquete no exige de forma efectiva cero trabajos para la etiqueta 33.'
}

if (($sql | Select-String -Pattern '(?im)^\s*UPDATE\s+nav\.operaciones\s*$' -AllMatches).Matches.Count -ne 1) {
    throw 'El paquete debe modificar exactamente una vez nav.operaciones.'
}

if ($sql -match '(?im)^\s*(?:UPDATE|INSERT|MERGE)\s+(?:imp\.|prod\.|nav\.intentos_operacion\b)') {
    throw 'El paquete no puede modificar produccion, intentos ni impresion.'
}

[pscustomobject]@{
    Package = '039A'
    DatabaseGuard = $true
    Transactional = $true
    NavContact = $false
    ExactOperation = 41
    ExactPallet = 31
    ExactOrder = 31
    ExternalIdentifier = 26846
    LabelRemainsPendingNav = 33
    PrintJobsRemainZero = $true
    FinalPallet = $true
    ExactSupervisor = 48
    Audited = $true
}
