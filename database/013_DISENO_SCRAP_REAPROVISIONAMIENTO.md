# Diseño 013 — scrap y reaprovisionamiento

Estado: diseño ejecutado mediante `013A–013D`; paquete instalado, probado,
limpiado y validado el 29/07/2026.

Base única prevista: `EBIR_MES_TEST`.

## Objetivo

Completar la operativa transaccional de:

- registro de scrap por operario o supervisor;
- corrección o anulación por supervisor sin alterar el histórico;
- creación opcional y explícita de solicitudes de reaprovisionamiento;
- gestión de esas solicitudes por un aprovisionador;
- persistencia idempotente de los consumos y ajustes que más tarde enviará la
  integración NAV.

Los procedimientos de este paquete no llamarán a NAV, RFID, dispositivos ni
impresoras. La capa SQL recibirá identidades de empleado ya resueltas y
únicamente confirmará cambios locales.

## Reglas funcionales consolidadas

1. Todo scrap pertenece a una FL, una sesión y una línea concretas.
2. Todo scrap selecciona un componente concreto importado desde NAV para esa
   FL, incluso cuando el motivo pertenece a la categoría `LUNA`.
3. La cantidad de scrap debe ser entera y positiva.
4. Los motivos se toman de `[log].motivos_scrap` y deben estar activos.
5. Si el motivo exige descripción, no se admite una descripción vacía.
6. Puede registrar scrap un empleado activo con rol activo `OPERARIO` o
   `SUPERVISOR`.
7. Solo un supervisor activo puede corregir o anular scrap, siempre con motivo.
8. Una corrección no modifica el registro original: añade una revisión
   numerada e inmutable.
9. La cantidad efectiva es la de la revisión más reciente; si no hay revisión,
   es la cantidad original. Una anulación deja cantidad efectiva cero.
10. `prod.ordenes.cantidad_scrap_acumulada` mantiene la suma de las cantidades
    efectivas.
11. El scrap nunca reduce el objetivo de unidades buenas:

```text
cantidad_pendiente_buena =
cantidad_objetivo_buena - cantidad_buena_cerrada
```

12. Cada alta genera una operación local `CONSUMO_SCRAP`.
13. Cada corrección genera `AJUSTE_CONSUMO_SCRAP`; cada anulación,
    `ANULACION_CONSUMO`.
14. El fallo o retraso de NAV no revierte el scrap físico ni detiene la
    producción. El cierre final de la FL deberá bloquearse en su paquete
    específico mientras existan consumos sin confirmar.
15. Tras registrar scrap, solicitar reposición es una decisión explícita. No
    se crea automáticamente.

## Modelo existente reutilizado

No se proponen tablas, columnas, índices, restricciones ni catálogos nuevos.
Se reutilizan:

- `[log].motivos_scrap`;
- `[log].scrap`;
- `[log].revisiones_scrap`;
- `[log].solicitudes_reaprovisionamiento`;
- `[log].historial_solicitudes`;
- `nav.componentes_orden`;
- `nav.operaciones`;
- `prod.ordenes`;
- `prod.sesiones_linea`;
- `seg.empleados`, `seg.roles` y `seg.empleados_roles`;
- `aud.eventos`.

## Procedimientos propuestos

### `[log].registrar_scrap`

Contrato previsto:

```sql
@sesion_linea_id             bigint,
@componente_orden_id         bigint,
@motivo_scrap_id             smallint,
@cantidad                    int,
@descripcion                 nvarchar(1000) = NULL,
@registrado_por_empleado_id  bigint,
@correlacion_id              uniqueidentifier,
@scrap_id                    bigint OUTPUT,
@operacion_nav_id            bigint OUTPUT
```

Dentro de una única transacción:

1. normaliza texto y valida parámetros;
2. bloquea la sesión, la orden y el componente en orden estable;
3. exige sesión activa en `CARGADA`, `PRODUCIENDO`, `SIN_OPERARIOS` o
   `STANDBY`;
4. valida empleado activo y rol `OPERARIO` o `SUPERVISOR`;
5. valida componente de la misma orden y motivo activo;
6. inserta `[log].scrap` con snapshots del componente;
7. incrementa `cantidad_scrap_acumulada`, sin modificar cantidad buena,
   objetivo ni pendiente;
8. inserta en `nav.operaciones` una fila `CONSUMO_SCRAP`, estado `PENDIENTE`,
   con payload JSON y clave `SCRAP:{scrap_uid}:R0`;
9. audita `SCRAP_REGISTRADO`.

La misma `@correlacion_id` repetida no debe crear un segundo scrap. Como
`aud.eventos.correlacion_id` no posee unicidad física, el procedimiento tomará
primero un `sp_getapplock` transaccional exclusivo sobre
`MES:CORRELACION:{correlacion_id}`. Después consultará el evento anterior y
devolverá el scrap y la operación ya asociados. La correlación es obligatoria
y constituye la idempotencia de la acción de usuario; la clave de
`nav.operaciones` protege además la cola de integración.

### `[log].revisar_scrap`

Contrato previsto:

```sql
@scrap_id                       bigint,
@componente_orden_id            bigint,
@motivo_scrap_id                smallint,
@cantidad                       int,
@descripcion                    nvarchar(1000) = NULL,
@es_anulacion                   bit,
@ajustado_por_supervisor_id     bigint,
@motivo_ajuste                  nvarchar(500),
@correlacion_id                 uniqueidentifier,
@revision_scrap_id              bigint OUTPUT,
@operacion_nav_id               bigint OUTPUT
```

La revisión representa el nuevo valor completo, no un delta. El procedimiento:

1. bloquea scrap, revisiones, orden y operaciones NAV relacionadas;
2. valida supervisor activo;
3. rechaza una revisión idéntica al valor efectivo actual;
4. exige cantidad cero al anular y positiva al corregir;
5. valida componente, motivo y descripción con las mismas reglas del alta;
6. rechaza la corrección si la última operación NAV del scrap está
   `PROCESANDO` o `RESULTADO_DESCONOCIDO`;
7. asigna `numero_revision = MAX(numero_revision) + 1`;
8. inserta la revisión y snapshots, sin actualizar filas históricas;
9. ajusta `cantidad_scrap_acumulada` por:

```text
delta = nueva_cantidad_efectiva - cantidad_efectiva_anterior
```

10. crea una operación `AJUSTE_CONSUMO_SCRAP` o `ANULACION_CONSUMO` con clave
    `SCRAP:{scrap_uid}:R{numero_revision}`;
11. audita `SCRAP_CORREGIDO` o `SCRAP_ANULADO`, incluyendo valores anterior y
    nuevo.

Se admiten revisiones después de una operación `CONFIRMADA`,
`ERROR_REINTENTABLE` o `ERROR_DEFINITIVO`: la cola conserva cada cambio en
orden. No se admite revisar con resultado incierto porque podría desconocerse
qué consumo existe realmente en NAV.

### `[log].crear_solicitud_reaprovisionamiento`

Contrato previsto:

```sql
@sesion_linea_id              bigint,
@componente_orden_id          bigint,
@cantidad_solicitada          int,
@solicitada_por_empleado_id   bigint,
@scrap_id                     bigint = NULL,
@correlacion_id               uniqueidentifier,
@solicitud_id                 bigint OUTPUT
```

Reglas:

- la cantidad es positiva;
- la sesión está activa y el componente pertenece a su orden;
- el solicitante es `OPERARIO` o `SUPERVISOR` activo;
- si se indica scrap, pertenece a la misma orden, sesión, línea y componente;
- se permite una solicitud sin scrap para cubrir falta de material ordinaria;
- se inserta en estado `PENDIENTE`;
- se añade la primera fila de historial, desde `NULL` a `PENDIENTE`;
- se audita `REAPROVISIONAMIENTO_SOLICITADO`;
- la correlación repetida devuelve la solicitud existente.

No se impide que existan varias solicitudes abiertas del mismo componente:
pueden corresponder a necesidades físicas distintas. La interfaz deberá
mostrar las abiertas antes de confirmar para evitar duplicados accidentales;
la idempotencia evita el doble clic de una misma acción.

### `[log].transicionar_solicitud_reaprovisionamiento`

Contrato previsto:

```sql
@solicitud_id             bigint,
@estado_nuevo             nvarchar(20),
@empleado_id              bigint,
@comentario               nvarchar(500) = NULL,
@correlacion_id           uniqueidentifier
```

Exige empleado activo con rol activo `APROVISIONADOR`. Estados permitidos:

```text
PENDIENTE -> ACEPTADA | RECHAZADA | CANCELADA
ACEPTADA  -> EN_CAMINO | RECHAZADA | CANCELADA
EN_CAMINO -> ENTREGADA | CANCELADA
```

`ENTREGADA`, `RECHAZADA` y `CANCELADA` son terminales.

- `ACEPTADA` asigna la solicitud al aprovisionador y fija `aceptada_utc`.
- Las transiciones posteriores deben realizarlas el aprovisionador asignado.
- `EN_CAMINO` fija `en_camino_utc`.
- `ENTREGADA` fija `entregada_utc`.
- `RECHAZADA` exige comentario y lo copia a `motivo_rechazo`.
- `CANCELADA` exige comentario y lo copia a `motivo_cancelacion`.
- Cada transición inserta historial y auditoría.
- Repetir la misma correlación devuelve éxito idempotente si el resultado ya
  coincide; otro uso de esa correlación se rechaza.

La prioridad visual no requiere persistencia adicional. Se calcula desde
`solicitada_utc`:

```text
VERDE     < 10 minutos
AMARILLO  >= 10 y < 20 minutos
ROJO      >= 20 minutos
```

Los umbrales quedan como regla de presentación hasta que exista configuración
funcional específica.

## Concurrencia y bloqueo

Todos los procedimientos usarán:

- `SET XACT_ABORT ON`;
- `TRY/CATCH`, `ROLLBACK` y `THROW`;
- `SYSUTCDATETIME()` como única hora de escritura;
- `sp_getapplock` transaccional por correlación antes de buscar o crear el
  evento idempotente;
- `sp_getapplock` transaccional por scrap para serializar sus revisiones con
  la creación de solicitudes vinculadas;
- bloqueos `UPDLOCK, HOLDLOCK` sobre las filas que gobiernan la transición;
- orden estable: sesión/solicitud, orden, entidad principal, histórico y cola;
- revalidación de estado y rol dentro de la transacción.

Casos que deben producir un único ganador:

- dos altas con la misma correlación;
- dos supervisores revisando el mismo scrap;
- dos aprovisionadores aceptando la misma solicitud;
- aceptar y rechazar simultáneamente;
- entregar y cancelar simultáneamente.

## Auditoría

Eventos mínimos:

- `SCRAP_REGISTRADO`;
- `SCRAP_CORREGIDO`;
- `SCRAP_ANULADO`;
- `REAPROVISIONAMIENTO_SOLICITADO`;
- `REAPROVISIONAMIENTO_ACEPTADO`;
- `REAPROVISIONAMIENTO_EN_CAMINO`;
- `REAPROVISIONAMIENTO_ENTREGADO`;
- `REAPROVISIONAMIENTO_RECHAZADO`;
- `REAPROVISIONAMIENTO_CANCELADO`.

Los valores JSON no incluirán RFID ni secretos. Las revisiones guardarán el
valor efectivo completo anterior y nuevo; las transiciones guardarán estado,
asignación y marcas temporales relevantes.

## Permisos

Cada procedimiento concederá únicamente `EXECUTE` a `mes_runtime`. No se
añaden escrituras directas, DDL, lectura de auditoría ni control de base.

La lectura funcional existente sobre `[log]` permite construir los paneles de
scrap y reaprovisionamiento. Las acciones se canalizan exclusivamente por los
procedimientos.

## Scripts previstos

```text
013A_registrar_scrap.sql — preparado para revisión estática
013B_revisar_scrap.sql — preparado para revisión estática
013C_crear_solicitud_reaprovisionamiento.sql — preparado para revisión estática
013D_transicionar_solicitud_reaprovisionamiento.sql — preparado para revisión estática
013_README.md — preparado
```

No se incluye todavía el envío, confirmación o reintento de operaciones NAV.
Ese flujo formará un paquete separado y reutilizará `nav.operaciones` e
`nav.intentos_operacion`.

## Pruebas mínimas futuras

1. Alta por operario y por supervisor.
2. Rechazo por rol, sesión, componente, motivo, descripción o cantidad.
3. Alta idempotente por doble envío.
4. Scrap incrementa acumulado y no altera el objetivo bueno.
5. Corrección y anulación ajustan el acumulado por delta.
6. Revisión concurrente con un único número ganador.
7. Bloqueo de revisión con resultado NAV incierto.
8. Solicitud vinculada a scrap y solicitud ordinaria sin scrap.
9. Historial completo de todos los estados.
10. Rechazo y cancelación con motivo obligatorio.
11. Aprovisionador asignado y exclusión de un segundo aprovisionador.
12. Transiciones terminales rechazadas.
13. Concurrencia entre aceptación/rechazo y entrega/cancelación.
14. Auditoría, permisos mínimos y ausencia de RFID.
15. Limpieza total de fixtures y `DBCC CHECKDB`.

## Orden de preparación

1. revisar conjuntamente este diseño;
2. preparar `013A`;
3. preparar `013B`;
4. preparar `013C`;
5. preparar `013D`;
6. preparar README y pruebas;
7. revisar estáticamente el paquete completo;
8. solicitar autorizaciones separadas para instalación, fixtures, pruebas
   funcionales, concurrencia, permisos y limpieza.
