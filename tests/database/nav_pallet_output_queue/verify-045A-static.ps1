$ErrorActionPreference = 'Stop'
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$path=Join-Path $root 'database\045A_confirmar_reconciliacion_tardia_salida_palet_55.sql'
$sql=Get-Content -LiteralPath $path -Raw
$required=@(
    "IF DB_NAME() <> N'EBIR_MES_TEST'",'BEGIN TRANSACTION','BEGIN CATCH',
    'ROLLBACK TRANSACTION','operacion_nav_id=55',
    "n.estado=N'RESULTADO_DESCONOCIDO' AND n.numero_intentos=12",
    "n.identificador_externo=N'26859'",
    "o.orden_id=38 AND o.numero_orden=N'FL26-00009'",
    'o.cantidad_objetivo=80 AND o.cantidad_buena_acumulada=20',
    'o.cantidad_reservada_activa=20',
    'p.palet_id=44 AND p.numero_palet=1 AND p.cantidad_buena=20',
    'p.es_ultimo=0 AND p.autorizado_por_supervisor_id IS NULL',
    'numero_intento=12',
    "JSON_VALUE(respuesta,'$.reason')=N'OutputStateNotRegistered'",
    'etiqueta_id=46 AND orden_id=38 AND palet_id=44',
    'EXEC nav.confirmar_salida_palet',"@identificador_externo=N'26859'",
    'SUPERVISED_EXISTING_OUTPUT',"estado=N'CONFIRMADA'",'numero_intentos=13',
    "tipo=N'PALET' AND estado=N'LISTA'","es_reimpresion=0 AND estado=N'PENDIENTE'",
    'WITH (UPDLOCK,HOLDLOCK)'
)
foreach($token in $required){if(-not $sql.Contains($token)){throw "Falta el contrato requerido: $token"}}
if($sql -match '(?im)^\s*USE\s+' -or $sql -match '(?i)\b(?!EBIR_MES_TEST\b)[A-Za-z0-9_]+\.(?:nav|prod|imp|cfg|seg|aud)\.'){
    throw 'Referencia de base no permitida.'
}
if($sql -match '(?i)\b(?:TRUNCATE|DROP|DELETE|MERGE)\b'){
    throw '045A no puede eliminar ni fusionar datos u objetos.'
}
if($sql -match '(?i)RegistrarSalidaFabricacion|https?://|OPENROWSET|OPENDATASOURCE|sp_OA|xp_cmdshell'){
    throw '045A contiene contacto externo no permitido.'
}
if($sql -match '(?im)^\s*(?:UPDATE|INSERT|MERGE)\s+(?:imp\.|prod\.|nav\.)'){
    throw '045A solo puede mutar mediante el procedimiento operativo publicado.'
}
if(($sql|Select-String -Pattern '(?i)EXEC nav\.confirmar_salida_palet' -AllMatches).Matches.Count -ne 1){
    throw '045A debe confirmar exactamente una vez.'
}
[pscustomobject]@{Package='045A';DatabaseGuard=$true;NavContact=$false;ExactOperation=55;ExactLabel=46;ExternalIdentifier=26859;OriginalPrintJob=1}
