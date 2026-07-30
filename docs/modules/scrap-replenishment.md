# Scrap y reaprovisionamiento

Incluye el registro y revisión de scrap, la creación de solicitudes de
reaprovisionamiento y sus transiciones de estado.

La definición vigente se encuentra en:

- `database/013_DISENO_SCRAP_REAPROVISIONAMIENTO.md`

El frontend no debe inventar estados ni transiciones: presenta exclusivamente
las acciones autorizadas por el backend.

## Registro de scrap

`POST /api/line-sessions/{sessionId}/scrap` recibe `orderComponentId`,
`scrapReasonId`, `quantity`, `description`, `registeredByEmployeeId` y
`correlationId`. Los identificadores y la cantidad deben ser positivos; la
descripción opcional se normaliza y no puede superar 1000 caracteres.

Una respuesta `201` incluye el identificador de scrap, la operación NAV local
pendiente y la correlación. El endpoint no llama a NAV. Los rechazos
`55000–55016` se traducen a códigos funcionales seguros; las solicitudes
inválidas devuelven `400`, los conflictos `409` y los fallos no clasificados
se ocultan tras `503`.

## Revisión y anulación de scrap

`POST /api/scrap/{scrapId}/revisions` recibe `orderComponentId`,
`scrapReasonId`, `quantity`, `description`, `isCancellation`,
`adjustedBySupervisorId`, `adjustmentReason` y `correlationId`. Una corrección
requiere cantidad positiva y una anulación cantidad cero. El motivo de ajuste
es obligatorio y no puede superar 500 caracteres; la descripción opcional no
puede superar 1000.

Una respuesta `201` incluye la revisión, la operación NAV local pendiente, el
scrap original, el tipo de revisión y la correlación. El endpoint no llama a
NAV. Los rechazos `55100–55122` se traducen a códigos funcionales seguros; las
solicitudes inválidas devuelven `400`, los conflictos `409` y los fallos no
clasificados se ocultan tras `503`.

## Creación de solicitud de reaprovisionamiento

`POST /api/line-sessions/{sessionId}/replenishment-requests` recibe
`orderComponentId`, `requestedQuantity`, `requestedByEmployeeId`, `scrapId`
opcional y `correlationId`. Los identificadores informados y la cantidad deben
ser positivos. La solicitud puede responder a una falta ordinaria o vincularse
al valor efectivo de un scrap de la misma sesión.

Una respuesta `201` incluye la solicitud en estado `PENDIENTE`, el scrap
vinculado —si existe— y la correlación. Los rechazos `55200–55217` se traducen
a códigos funcionales seguros; las solicitudes inválidas devuelven `400`, los
conflictos `409` y los fallos no clasificados se ocultan tras `503`.
