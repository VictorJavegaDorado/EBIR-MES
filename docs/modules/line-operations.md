# Operación de línea

Incluye identificación de línea, apertura de sesión, turnos, entradas, salidas,
ausencias, sustituciones y finalización de sesión.

La base normativa detallada está en los paquetes SQL 011 y 012:

- `database/011_DISENO_SESIONES_TURNOS_FICHAJES.md`
- `database/012_DISENO_AUSENCIAS_SUSTITUCIONES_CORRECCIONES.md`

La API será la única autoridad para iniciar y finalizar estas transiciones. El
cliente muestra el estado devuelto y no reconstruye las reglas horarias.

## Apertura de sesión

`POST /api/line-sessions` recibe `orderId`, `lineId`, `palletFormatOrderId`,
`supervisorId`, `outsideScheduleConfirmed` y `correlationId`. Los cuatro
identificadores deben ser positivos y `correlationId` debe ser un UUID distinto
de cero.

Una apertura correcta devuelve `201` con el identificador de sesión y conserva
el identificador de correlación. Los rechazos productivos conocidos del
procedimiento `prod.abrir_sesion_linea` devuelven `409` mediante códigos
funcionales estables. Las solicitudes inválidas devuelven `400` y los fallos no
clasificados de infraestructura devuelven `503`; nunca se exponen números,
mensajes ni objetos internos de SQL Server.

## Entrada productiva

`POST /api/line-sessions/{sessionId}/entries` recibe `employeeId` y
`correlationId`. La sesión y el empleado deben ser identificadores positivos;
la correlación debe ser un UUID distinto de cero.

Una entrada correcta devuelve `201` con el identificador de fichaje, la reserva
de palé creada en el primer inicio —o `null` si no corresponde crearla— y la
correlación recibida. Los rechazos conocidos de
`prod.registrar_entrada_productiva` devuelven `409` con códigos funcionales. Los
errores SQL no clasificados se ocultan tras `503`.

## Salida productiva

`POST /api/line-sessions/{sessionId}/exits` recibe `employeeId` y
`correlationId`, con las mismas reglas de identificadores que la entrada.

Una salida correcta devuelve `200`, el número de recursos productivos que
permanecen activos en la sesión y la correlación recibida. Los rechazos
conocidos de `prod.registrar_salida_productiva` devuelven `409`; las solicitudes
inválidas devuelven `400` y los fallos no clasificados se ocultan tras `503`.

## Cambio de turno pendiente

`POST /api/line-sessions/{sessionId}/shift-change-pending` recibe
`correlationId`. La sesión debe ser positiva y la correlación un UUID distinto
de cero.

La operación es idempotente: devuelve `200` y `changeMarked` indica si esta
ejecución realizó el cambio (`true`) o si ya estaba pendiente (`false`). Los
rechazos conocidos de `prod.marcar_cambio_turno_pendiente` devuelven `409`; las
solicitudes inválidas devuelven `400` y los fallos no clasificados se ocultan
tras `503`.

## Finalización de sesión de turno

`POST /api/line-sessions/{sessionId}/finish-shift` recibe `supervisorId` y
`correlationId`. Ambos identificadores y la sesión deben ser válidos y
positivos.

Una finalización correcta devuelve `200`, el número de fichajes cerrados por el
sistema y la correlación recibida. Los rechazos conocidos de
`prod.finalizar_sesion_turno` devuelven `409` mediante códigos funcionales que
no exponen detalles de NAV, impresión o SQL. Las solicitudes inválidas
devuelven `400` y los fallos no clasificados se ocultan tras `503`.

## Inicio de paro de operario

`POST /api/line-sessions/{sessionId}/operator-stops` recibe `employeeId`,
`reason` y `correlationId`. Los motivos admitidos son `WC` y `PAUSA_CALOR`.

Una operación correcta devuelve `201` con el identificador del paro, los
recursos productivos que permanecen activos y la correlación. Los rechazos
conocidos de `prod.iniciar_paro_operario` (`52200–52213`) se traducen a códigos
funcionales; las solicitudes inválidas devuelven `400`, los conflictos `409` y
los fallos no clasificados se ocultan tras `503`.

## Finalización de paro de operario

`POST /api/line-sessions/{sessionId}/operator-stops/finish` recibe `employeeId`
y `correlationId`. Una respuesta `200` incluye el paro finalizado, la
sustitución finalizada automáticamente —si existe— y los recursos activos.
Los rechazos `52300–52317` se traducen a códigos funcionales seguros; las
solicitudes inválidas devuelven `400`, los conflictos `409` y los fallos no
clasificados se ocultan tras `503`.
