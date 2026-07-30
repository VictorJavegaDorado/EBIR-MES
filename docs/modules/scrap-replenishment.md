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
