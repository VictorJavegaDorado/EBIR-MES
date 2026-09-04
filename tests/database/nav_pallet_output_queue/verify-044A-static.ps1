$ErrorActionPreference = 'Stop'
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$path=Join-Path $root 'database\044A_confirmar_reconciliacion_tardia_salida_palet_50.sql'
$sql=Get-Content -LiteralPath $path -Raw
$required=@(
    "IF DB_NAME() <> N'EBIR_MES_TEST'",'BEGIN TRANSACTION','BEGIN CATCH',
    'ROLLBACK TRANSACTION','operacion_nav_id=50',
    "n.estado=N'RESULTADO_DESCONOCIDO' AND n.numero_intentos=12",
    "n.identificador_externo=N'26854'",
    "o.orden_id=36 AND o.numero_orden=N'FL26-00008'",
    'o.cantidad_objetivo=100 AND o.cantidad_buena_acumulada=20',
    'o.cantidad_reservada_activa=20',
    'p.palet_id=39 AND p.numero_palet=1 AND p.cantidad_buena=20',
    'p.es_ultimo=0 AND p.autorizado_por_supervisor_id IS NULL',
    'numero_intento=12',
    "JSON_VALUE(respuesta,'$.reason')=N'OutputStillPending'",
    'etiqueta_id=41 AND orden_id=36 AND palet_id=39',
    'EXEC nav.confirmar_salida_palet',"@identificador_externo=N'26854'",
    'SUPERVISED_EXISTING_OUTPUT',"estado=N'CONFIRMADA'",'numero_intentos=13',
    "tipo=N'PALET' AND estado=N'LISTA'","es_reimpresion=0 AND estado=N'PENDIENTE'",
    'WITH (UPDLOCK,HOLDLOCK)'
)
foreach($token in $required){if(-not $sql.Contains($token)){throw "Falta el contrato requerido: $token"}}
if($sql -match '(?im)^\s*USE\s+' -or $sql -match '(?i)\b(?!EBIR_MES_TEST\b)[A-Za-z0-9_]+\.(?:nav|prod|imp|cfg|seg|aud)\.'){
    throw 'Referencia de base no permitida.'
}
if($sql -match '(?i)\b(?:TRUNCATE|DROP|DELETE|MERGE)\b'){
    throw '044A no puede eliminar ni fusionar datos u objetos.'
}
if($sql -match '(?i)RegistrarSalidaFabricacion|https?://|OPENROWSET|OPENDATASOURCE|sp_OA|xp_cmdshell'){
    throw '044A contiene contacto externo no permitido.'
}
if($sql -match '(?im)^\s*(?:UPDATE|INSERT|MERGE)\s+(?:imp\.|prod\.|nav\.)'){
    throw '044A solo puede mutar mediante el procedimiento operativo publicado.'
}
if(($sql|Select-String -Pattern '(?i)EXEC nav\.confirmar_salida_palet' -AllMatches).Matches.Count -ne 1){
    throw '044A debe confirmar exactamente una vez.'
}
[pscustomobject]@{Package='044A';DatabaseGuard=$true;NavContact=$false;ExactOperation=50;ExactLabel=41;ExternalIdentifier=26854;OriginalPrintJob=1}
