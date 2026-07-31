# Sincronización de órdenes de producción

## Objetivo

MES consulta órdenes de producción publicadas por NAV y las traduce a un
contrato estable de aplicación. La primera fase es exclusivamente de lectura y
no persiste datos ni ejecuta operaciones en NAV.

## Alcance inicial

- Fuente: página SOAP `WS_CPP_ProdOrderList`.
- Operación permitida: `ReadMultiple`.
- Estado inicial de trabajo: órdenes lanzadas (`Released`).
- Cada consulta exige un límite entre 1 y 100 registros.
- La autenticación se delega a la identidad del proceso; no se guardan
  credenciales en código ni configuración versionada.
- Las llamadas solo se producen cuando un caso de uso invoca el adaptador. El
  registro en API o Worker queda fuera de esta fase.

## Resiliencia

Las lecturas pueden repetirse porque no cambian estado. Se reintentan como
máximo tres veces ante timeouts, errores de transporte, `408`, `429` o respuestas
`5xx`. Los errores funcionales y respuestas SOAP no válidas no se reintentan.

## Límites pendientes de autorización

- Persistir o actualizar órdenes en `EBIR_MES_TEST`.
- Invocar codeunits que registren tiempos, consumos, salidas o cierres.
- Activar el adaptador en API, Worker o IIS.
- Contactar RFID o impresoras.
