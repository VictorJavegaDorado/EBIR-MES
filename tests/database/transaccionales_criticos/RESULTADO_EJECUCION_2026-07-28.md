# Resultado de ejecución — 28/07/2026

Base exclusiva: `EBIR_MES_TEST`.

## Fase 00 — fixtures

Resultado: correcto.

- 1 empresa NAV sintética.
- 1 impresora simulada.
- 7 líneas y 7 asignaciones de impresora.
- 3 empleados y 3 asignaciones de rol.
- 5 órdenes y 5 formatos.
- 7 sesiones y 7 estados de línea.
- 0 RFID sintéticos.
- 0 dispositivos asignados.

## Fase 01 — pruebas secuenciales

Resultado: detenida después del caso 2.

Mensajes obtenidos:

```text
OK 1 - Reserva valida
OK 2a - Sobre-reserva secuencial rechazada
La transacción actual no se puede confirmar ni admite operaciones que
escriban en el archivo de registro. Revierta la transacción.
```

### Entrada y estado previo

- Orden `ZZT-FL-TX-01`.
- Objetivo: 60.
- Buenas: 0.
- Reserva activa creada correctamente: 20.
- Segundo intento de reserva sobre la misma sesión.

### Resultado funcional del caso 2

El segundo intento produjo el error de negocio esperado `51204`:

```text
La sesion ya tiene una reserva activa.
```

### Defecto transaccional observado

`prod.reservar_palet` inicia una transacción antes de comprobar si la sesión ya
tiene una reserva activa. El `THROW 51204`, combinado con `XACT_ABORT ON`, deja
la transacción de la conexión sin posibilidad de confirmación. El procedimiento
no dispone de un bloque `TRY/CATCH` que ejecute `ROLLBACK` antes de propagar el
error.

El script de prueba capturó correctamente `51204`, pero la siguiente escritura
del caso 3 fue rechazada porque la conexión seguía dentro de la transacción no
confirmable.

Al cerrarse la conexión de ejecución, SQL Server revirtió automáticamente la
transacción pendiente del segundo intento.

### Estado persistido comprobado

Para `ZZT-FL-TX-01`:

```text
cantidad_buena_acumulada  = 0
cantidad_reservada_activa = 20
estado                    = ABIERTA
reservas_activas          = 1
reservas_canceladas       = 0
palets                    = 0
operaciones_nav           = 0
etiquetas                 = 0
eventos_auditoria         = 1
```

Solo quedó confirmada la reserva válida del caso 1.

## Decisión pendiente

- No se continuó con los casos 3–8.
- No se ejecutaron concurrencia, auditoría/permisos ni limpieza.

## Paquete 010 — aplicado y validado

Con autorización expresa se aplicó:

```text
database/010_refuerzo_transacciones_procedimientos.sql
```

Resultado estructural:

```text
procedimientos objetivo     = 5
procedimientos reforzados   = 5
tablas                      = 37
procedimientos críticos     = 6
```

Se repitió el segundo intento de reserva sobre la sesión que ya conservaba una
reserva activa. Resultado:

```text
error_numero = 51204
@@TRANCOUNT  = 0
XACT_STATE() = 0
```

El error funcional y su mensaje se conservan, y la conexión ya no queda dentro
de una transacción pendiente o no confirmable.

No se modificaron tablas, datos, permisos, contratos ni lógica funcional. Los
fixtures y la reserva válida del caso 1 permanecen cargados para continuar las
pruebas con autorización.

## Fase 01B — reanudación de casos 3–8

Con autorización expresa se ejecutó:

```text
tests/transaccionales_criticos/01B_REANUDAR_CASOS_3_A_8.sql
```

Resultado:

```text
OK PRECONDICIONES - Reanudacion desde el caso 3
OK 3 - Cancelacion supervisada
OK 4 - Cierre ordinario
OK 5 - NAV simulado
OK 6 - Impresion y desbloqueo
OK 7 - Multilinea: cierre ordinario y ultimo palet supervisado
OK 8 - Ultimo palet y CIERRE_FL
```

Estado comprobado después de la ejecución:

| Orden | Objetivo | Buenas | Reservadas | Reservas activas | Palés | Salidas de palé | Cierres FL | Estado |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| `ZZT-FL-TX-01` | 60 | 20 | 20 | 1 | 1 | 1 | 0 | `ABIERTA` |
| `ZZT-FL-TX-04` | 20 | 20 | 0 | 0 | 1 | 1 | 1 | `PENDIENTE_NAV` |
| `ZZT-FL-TX-05` | 40 | 40 | 0 | 0 | 2 | 2 | 0 | `PENDIENTE_CIERRE` |

La reserva activa de `ZZT-FL-TX-01` es la siguiente reserva automática creada
después de su cierre ordinario. En `ZZT-FL-TX-05` las dos salidas de palé
continúan pendientes de la simulación NAV/impresión, por lo que todavía no se
ha creado su operación `CIERRE_FL`.

Quedan pendientes:

- auditoría y permisos;
- limpieza completa y `DBCC CHECKDB`.

## Fase 02/03 — concurrencia multilínea

Se ejecutaron con autorización expresa dos conexiones independientes con inicio
UTC común:

```text
2026-07-28T13:29:44.978Z
```

Ambas intentaron reservar 20 unidades sobre `ZZT-FL-TX-02`, cuyo estado previo
era objetivo 100, buenas 80 y reservadas 0.

Resultado persistido:

```text
cantidad_objetivo         = 100
cantidad_buena_acumulada  = 80
cantidad_reservada_activa = 20
reservas_activas          = 1
eventos_reserva           = 1
```

Ganó la sesión de `ZZT-TX-02`, empleado `ZZT-EMP-TX-OP1`. La reserva confirmada
tiene cantidad 20. La otra conexión terminó sin dejar una segunda reserva.

Se repitió de forma controlada una solicitud sobre la línea perdedora para
capturar explícitamente el contrato de rechazo:

```text
error_numero = 51205
mensaje      = La reserva supera el pendiente disponible global.
@@TRANCOUNT  = 0
XACT_STATE() = 0
```

La invariante global se mantuvo:

```text
buenas + reservadas = objetivo
80 + 20 = 100
```

## Fase 04 — auditoría y permisos

Resultado:

```text
OK 9 - Auditoria y permisos
```

Se confirmó:

- presencia de todos los tipos de auditoría esperados;
- correlación obligatoria en los eventos sintéticos;
- ausencia de referencias aparentes a RFID en sus campos auditados;
- `EBIR\MES$` puede ejecutar los cinco procedimientos operativos;
- `EBIR\MES$` no puede ejecutar directamente `aud.registrar_evento`;
- `EBIR\MES$` no puede leer `aud.eventos`;
- `EBIR\MES$` no puede crear tablas;
- `EBIR\MES$` no puede actualizar directamente `prod.ordenes`;
- `EBIR\MES$` no puede insertar directamente en `nav.operaciones`;
- `EBIR\MES$` no puede insertar directamente en
  `imp.trabajos_impresion`.

No se cambiaron roles, miembros ni concesiones durante esta prueba.

Solo queda pendiente la limpieza completa de fixtures y el
`DBCC CHECKDB`, que requieren autorización separada.

## Fase 99 — limpieza y comprobación final

Con autorización expresa se ejecutó:

```text
tests/transaccionales_criticos/99_LIMPIEZA_Y_CHECKDB.sql
```

Resultado:

```text
OK 10a - Fixtures eliminados
OK 10b - DBCC CHECKDB finalizado
```

Estado final verificado:

```text
tablas                  = 37
procedimientos críticos = 6
registros iniciales     = 37
fixtures                 = 0
miembros MES$ runtime   = 1
```

Tablas operativas comprobadas:

```text
empresas NAV        = 0
líneas              = 0
impresoras          = 0
empleados           = 0
RFID                = 0
órdenes             = 0
sesiones            = 0
reservas            = 0
palés               = 0
operaciones NAV     = 0
etiquetas           = 0
trabajos impresión  = 0
eventos auditoría   = 0
```

`DBCC CHECKDB (EBIR_MES_TEST)` terminó sin errores informados.

## Conclusión

El circuito crítico disponible queda validado:

- reserva válida;
- sobre-reserva y concurrencia multilínea;
- cancelación supervisada con motivo;
- cierre ordinario;
- confirmación NAV simulada;
- confirmación de impresión y desbloqueo;
- trabajo multilínea y último palé supervisado;
- creación no duplicada de `CIERRE_FL`;
- auditoría y permisos mínimos;
- limpieza completa e integridad final.

El defecto transaccional detectado quedó corregido mediante el paquete `010`,
aplicado y validado. La base vuelve a quedar sin configuración ficticia de
planta ni datos productivos.
