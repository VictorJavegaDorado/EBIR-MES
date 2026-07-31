# Sincronizacion de ordenes de produccion

## Objetivo

MES consulta ordenes de produccion publicadas por NAV, las traduce a un
contrato estable y prepara su persistencia idempotente en una bandeja de
entrada. NAV permanece exclusivamente en lectura.

## Alcance de lectura

- Cabeceras: `WS_CPP_ProdOrderList`.
- Lineas: `WS_CPP_ProdOrderLineList`.
- Ruta y operaciones: `WS_CPP_RutaOrdenProduccion`.
- Componentes: `WS_CPP_Componentes`.
- Unica operacion permitida: `ReadMultiple`.
- Estado inicial de trabajo: ordenes lanzadas (`Released`).
- Cada consulta exige un limite entre 1 y 100 registros.
- Las lecturas de detalle exigen un numero de orden exacto. Se rechazan rangos,
  comodines y operadores de filtro de NAV.
- La autenticacion se delega a la identidad del proceso; no se guardan
  credenciales en codigo ni configuracion versionada.
- Las llamadas solo se producen cuando un caso de uso invoca el adaptador.

La relacion de componentes conserva los numeros de linea de NAV. La pagina de
lineas publicada no expone su numero de linea, por lo que durante el piloto se
exige exactamente una linea por orden.

## Bandeja de entrada idempotente

El caso de uso lee por numero exacto una orden `Released`, su linea, ruta y
componentes. Normaliza entorno, empresa y orden, rechaza relaciones incoherentes
y no acepta exactamente 100 detalles para evitar persistir una pagina
posiblemente truncada.

El adaptador SQL serializa el snapshot completo de forma determinista, calcula
su SHA-256 y llama a `nav.aplicar_snapshot_orden`. El procedimiento preparado:

- serializa por correlacion y por orden mediante `sp_getapplock`;
- repite de forma segura una correlacion con el mismo snapshot;
- rechaza la misma correlacion con contenido distinto;
- devuelve `CREADA`, `ACTUALIZADA` o `SIN_CAMBIOS`;
- sustituye cabecera y detalles atomicamente cuando NAV ha cambiado.

La bandeja no alimenta todavia `prod.ordenes`. Ese paso requiere resolver de
forma explicita el lote obligatorio y confirmar la unidad de tiempo NAV; no se
inventan valores productivos.

## Resiliencia

Las lecturas pueden repetirse porque no cambian estado. Se reintentan como
maximo tres veces ante timeouts, errores de transporte, `408`, `429` o respuestas
`5xx`. Los errores funcionales y respuestas SOAP no validas no se reintentan.

## Estado y limites pendientes de autorizacion

- El paquete `015A_bandeja_entrada_ordenes_nav.sql` esta instalado y validado en
  `EBIR_MES_TEST`; la bandeja quedo vacia tras retirar la prueba.
- Registrar el caso de uso en API o Worker y programar su disparador.
- Promover snapshots desde `nav.*_entrada` a `prod.ordenes`.
- Invocar codeunits que registren tiempos, consumos, salidas o cierres.
- Activar el adaptador en API, Worker o IIS.
- Contactar RFID o impresoras.
