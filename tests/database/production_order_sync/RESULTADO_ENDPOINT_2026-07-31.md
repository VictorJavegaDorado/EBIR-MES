# Resultado del disparador HTTP NAV -> MES — 31/07/2026

## Alcance autorizado

Se valido el endpoint administrativo
`POST /api/admin/production-orders/synchronize` sin activar una release nueva,
sin modificar `runtime\current` y sin escribir en NAV.

- servidor: `MES.EBIR.LOCAL`;
- identidad de proceso: `NT AUTHORITY\Servicio de red`, presentada en red como
  `EBIR\MES$`;
- NAV: `EBIRTEST`, empresa `EBIR`, solo `ReadMultiple`;
- SQL: `SQL.EBIR.LOCAL\NAVISION2017`, exclusivamente `EBIR_MES_TEST`;
- orden exacta: `29516CI/1508`;
- correlacion: `ec6015ce-feea-4649-9192-01c6d3c9157b`.

La API se publico temporalmente y escucho solo en `127.0.0.1:50731`. La tarea
programada y la publicacion temporal se retiraron al terminar.

## Incidencia de configuracion inicial

El primer intento uso por error una raiz que ya incluia la empresa:
`.../EBIRTEST/WS/EBIR`. Como el adaptador agrega la empresa, la URL contenia
`/EBIR/EBIR/Page/` y NAV devolvio HTTP 500. El endpoint respondio con el `503`
seguro previsto y no persistio ninguna fila.

La raiz correcta termina en `/EBIRTEST/WS/`. Tras corregir solo esa
configuracion temporal se repitio la misma correlacion.

## Resultado

La primera llamada correcta devolvio:

- `inboundOrderId`: `2`;
- `outcome`: `CREADA`.

La repeticion con la misma correlacion devolvio exactamente el mismo ID y el
mismo resultado, confirmando la idempotencia HTTP -> caso de uso -> SQL.

| Objeto | Antes | Despues |
|---|---:|---:|
| `nav.ordenes_entrada` | 0 | 1 |
| `nav.lineas_orden_entrada` | 0 | 1 |
| `nav.rutas_orden_entrada` | 0 | 2 |
| `nav.componentes_orden_entrada` | 0 | 28 |
| `nav.sincronizaciones_orden` | 0 | 1 |

El snapshot se conserva intencionadamente como primera orden controlada de la
bandeja para el siguiente bloque de promocion. Todavia no alimenta
`prod.ordenes`.

## Estado operativo final

- tarea temporal eliminada;
- puerto local `50731` sin listener;
- publicacion temporal eliminada;
- evidencia operativa conservada en
  `runtime\shared\logs\manual-nav-sync-20260731-b5d8fa9.json`;
- `runtime\current` continua apuntando a
  `20260731.5-db4de52-combined`;
- IIS y su pool permanecen iniciados y sin cambios;
- no se invocaron codeunits ni operaciones de escritura NAV.
