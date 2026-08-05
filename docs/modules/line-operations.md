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

## Integracion con la mesa de produccion

La experiencia integrada y las reglas funcionales confirmadas se documentan
en `production-workstation.md`. El contrato administrativo
`POST /api/line-sessions` conserva la exigencia de supervisor. El corte de mesa
añade `POST /api/production-workstations/start-or-join`, que permite a un
operario productivo ordinario iniciar dentro de 06:00-22:00 y crea
conjuntamente sesion y primer fichaje. La misma operacion incorpora recursos
posteriores y es idempotente por correlacion. El paquete 023A que materializa
este contrato esta preparado, no instalado.

`GET /api/production-workstations/state` recibe `orderId` y `lineId` y expone
solo el estado operativo persistido: sesion, tiempos UTC derivados, capacidad,
formato POK y personas activas. No devuelve ni registra credenciales RFID.

## Inicio de sustitución de capacidad

`POST /api/line-sessions/{sessionId}/capacity-substitutions` recibe
`replacedOperatorId`, `substituteSupervisorId`, `reason` y `correlationId`.
El motivo es obligatorio, se normaliza y no puede superar 250 caracteres; las
dos personas deben ser distintas.

Una respuesta `201` incluye la sustitución, el fichaje productivo creado para
el supervisor y los recursos activos. Los rechazos `52400–52418` se traducen a
códigos funcionales seguros; las solicitudes inválidas devuelven `400`, los
conflictos `409` y los fallos no clasificados se ocultan tras `503`.

## Finalización de sustitución de capacidad

`POST /api/capacity-substitutions/{substitutionId}/finish` recibe
`supervisorId`, `reason` y `correlationId`. La sustitución y el supervisor deben
ser identificadores positivos; el motivo es obligatorio, se normaliza y no
puede superar 250 caracteres.

Una respuesta `200` incluye la sustitución finalizada, los recursos productivos
que permanecen activos y la correlación recibida. Los rechazos `52500–52519`
se traducen a códigos funcionales seguros; las solicitudes inválidas devuelven
`400`, los conflictos `409` y los fallos no clasificados se ocultan tras `503`.

## Corrección de fichaje del turno actual

`POST /api/time-entries/{timeEntryId}/corrections` recibe
`correctedEntryUtc`, `correctedExitUtc`, `supervisorId`, `reason` y
`correlationId`. Los instantes se normalizan a UTC; la entrada es obligatoria,
la salida es opcional y no puede precederla. El motivo es obligatorio, se
normaliza y no puede superar 500 caracteres.

Una respuesta `200` conserva el identificador del fichaje y la correlación.
Los rechazos `52600–52621` se traducen a códigos funcionales seguros; las
solicitudes inválidas devuelven `400`, los conflictos `409` y los fallos no
clasificados se ocultan tras `503`.
