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
