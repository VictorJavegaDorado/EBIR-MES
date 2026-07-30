# Paquete 013 — scrap y reaprovisionamiento

Estado: **instalado, probado y validado completamente el 29/07/2026; fixtures
eliminados y `DBCC CHECKDB` correcto**.

Base única autorizable: `EBIR_MES_TEST`.

## Alcance

El paquete completa la persistencia operativa de scrap, sus revisiones y las
solicitudes de reaprovisionamiento. No modifica el esquema físico ni llama a
NAV, RFID, impresoras o dispositivos.

Se apoya en las tablas y restricciones creadas por los paquetes `001–009` y en
los flujos de sesiones y recursos cerrados por `011–012`.

## Orden de instalación futuro

```text
013A_registrar_scrap.sql
013B_revisar_scrap.sql
013C_crear_solicitud_reaprovisionamiento.sql
013D_transicionar_solicitud_reaprovisionamiento.sql
```

Los cuatro scripts:

- abortan si la base actual no es `EBIR_MES_TEST`;
- usan `CREATE OR ALTER PROCEDURE`;
- no contienen cambios de tablas, índices, restricciones o datos;
- conceden únicamente `EXECUTE` sobre el nuevo procedimiento a
  `mes_runtime`;
- no ejecutan integraciones externas.

## Objetos añadidos

Procedimientos:

- `[log].registrar_scrap`;
- `[log].revisar_scrap`;
- `[log].crear_solicitud_reaprovisionamiento`;
- `[log].transicionar_solicitud_reaprovisionamiento`.

Tras una futura instalación correcta, el inventario esperado sería:

```text
37 tablas
20 procedimientos operativos/críticos
1 función interna
37 registros iniciales
```

El paquete no crea funciones, tablas ni registros iniciales.

## Scrap

Todo registro:

- pertenece a una sesión, orden y línea concretas;
- selecciona un componente importado para esa orden;
- utiliza un motivo activo;
- requiere cantidad entera positiva;
- puede realizarlo un `OPERARIO` o `SUPERVISOR` activo;
- incrementa `prod.ordenes.cantidad_scrap_acumulada`;
- no reduce `cantidad_objetivo` ni incrementa unidades buenas;
- crea localmente una operación `CONSUMO_SCRAP` en estado `PENDIENTE`;
- queda auditado.

No se llama a NAV dentro de la transacción. La integración consumirá después
la fila persistida en `nav.operaciones`.

## Revisiones y anulaciones

Solo un supervisor activo puede revisar scrap y debe informar un motivo.

El registro original nunca se actualiza. Cada cambio añade una fila numerada
en `[log].revisiones_scrap`; la revisión más reciente representa el valor
efectivo completo.

```text
delta = nueva cantidad efectiva - cantidad efectiva anterior
```

El delta actualiza el acumulado de la orden. Una corrección genera
`AJUSTE_CONSUMO_SCRAP` y una anulación genera `ANULACION_CONSUMO`.

No se permite revisar mientras la última operación NAV del scrap esté
`PROCESANDO` o `RESULTADO_DESCONOCIDO`.

## Solicitudes de reaprovisionamiento

La solicitud es siempre explícita: registrar scrap no la crea
automáticamente.

Puede:

- vincularse al valor efectivo de un scrap no anulado; o
- crearse sin scrap para una falta ordinaria de material.

La crea un operario o supervisor activo y nace en `PENDIENTE`, con su primera
fila de historial.

No se impone unicidad por componente porque dos necesidades físicas reales
pueden coexistir. La correlación protege dobles envíos de una misma acción.

## Máquina de estados

Las transiciones requieren un empleado activo con rol `APROVISIONADOR`:

```text
PENDIENTE -> ACEPTADA | RECHAZADA | CANCELADA
ACEPTADA  -> EN_CAMINO | RECHAZADA | CANCELADA
EN_CAMINO -> ENTREGADA | CANCELADA
```

`ENTREGADA`, `RECHAZADA` y `CANCELADA` son terminales.

Al aceptar, la solicitud queda asignada. Las transiciones posteriores solo
puede realizarlas ese aprovisionador. Rechazar o cancelar exige comentario.
Cada transición crea historial y auditoría.

La prioridad del panel se calcula desde `solicitada_utc`:

```text
VERDE     < 10 minutos
AMARILLO  >= 10 y < 20 minutos
ROJO      >= 20 minutos
```

## Idempotencia y concurrencia

Cada acción exige `correlacion_id`.

Como `aud.eventos.correlacion_id` no tiene restricción única, los
procedimientos toman un `sp_getapplock` transaccional exclusivo por
correlación antes de comprobar el evento anterior.

Las revisiones y solicitudes vinculadas toman además un bloqueo lógico por
scrap. Las entidades que gobiernan cada transición se leen con
`UPDLOCK, HOLDLOCK`.

Una repetición con la misma correlación y los mismos parámetros devuelve el
resultado anterior. Reutilizarla con otra acción o parámetros diferentes se
rechaza.

## Operaciones NAV persistidas

Claves previstas:

```text
SCRAP:{scrap_uid}:R0
SCRAP:{scrap_uid}:R{numero_revision}
```

Tipos:

- `CONSUMO_SCRAP`;
- `AJUSTE_CONSUMO_SCRAP`;
- `ANULACION_CONSUMO`.

El envío, la confirmación, el resultado desconocido y los reintentos NAV
quedan fuera de `013`. Se implementarán en un paquete específico apoyado en
`nav.operaciones` y `nav.intentos_operacion`.

El cierre final de la FL deberá comprobar posteriormente que no existen
consumos de scrap sin confirmar.

## Auditoría

Eventos:

- `SCRAP_REGISTRADO`;
- `SCRAP_CORREGIDO`;
- `SCRAP_ANULADO`;
- `REAPROVISIONAMIENTO_SOLICITADO`;
- `REAPROVISIONAMIENTO_ACEPTADO`;
- `REAPROVISIONAMIENTO_EN_CAMINO`;
- `REAPROVISIONAMIENTO_ENTREGADO`;
- `REAPROVISIONAMIENTO_RECHAZADO`;
- `REAPROVISIONAMIENTO_CANCELADO`.

No se almacenan referencias RFID, credenciales ni secretos.

## Transacciones y errores

Los cuatro procedimientos:

- usan `SET XACT_ABORT ON`;
- encapsulan las escrituras en `TRY/CATCH`;
- revierten con `ROLLBACK` antes de propagar el error;
- utilizan `SYSUTCDATETIME()`;
- validan estado, rol y relaciones dentro de la transacción;
- persisten entidad, cola NAV e auditoría atómicamente.

## Permisos

Solo se añade `EXECUTE` para `mes_runtime` sobre los cuatro procedimientos.

No se conceden escrituras directas, DDL, lectura de auditoría ni control de la
base. `EBIR\MES$` seguirá operando mediante el rol existente.

## Pruebas pendientes de preparar

El paquete de pruebas deberá cubrir:

1. altas válidas por operario y supervisor;
2. rechazos de sesión, orden, componente, motivo, descripción, cantidad y rol;
3. idempotencia y doble envío;
4. acumulado de scrap sin modificación del objetivo bueno;
5. corrección y anulación por delta;
6. revisiones concurrentes;
7. bloqueo por resultado NAV incierto;
8. solicitudes con scrap, sin scrap y sobre scrap anulado;
9. todas las transiciones y estados terminales;
10. asignación exclusiva al aprovisionador;
11. concurrencia de aceptación/rechazo y entrega/cancelación;
12. auditoría y permisos;
13. limpieza completa de fixtures;
14. `DBCC CHECKDB`.

Los fixtures deberán ser sintéticos, estar claramente identificados como
`ZZTEST_013`/`ZZ13-` y no incluir RFID, dispositivos ni impresoras reales.

## Fases futuras

Antes de ejecutar cualquier SQL:

1. revisar conjuntamente `013A–013D`;
2. preparar y revisar todas las pruebas;
3. solicitar autorización separada para instalación;
4. solicitar autorización separada para fixtures;
5. solicitar autorización separada para pruebas funcionales;
6. solicitar autorización separada para concurrencia;
7. solicitar autorización separada para auditoría y permisos;
8. solicitar autorización separada para limpieza y `DBCC CHECKDB`.

## Ejecución cerrada

Las fases anteriores se autorizaron y ejecutaron posteriormente de forma
separada sobre `EBIR_MES_TEST`.

Resultado:

```text
37 tablas
20 procedimientos
1 función interna
37 registros iniciales
0 filas operativas
0 fixtures ZZTEST_013/ZZ13-
4 permisos EXECUTE nuevos para mes_runtime
EBIR\MES$ miembro de mes_runtime
DBCC CHECKDB sin errores
```

Las pruebas funcionales terminaron correctamente. En concurrencia se ajustó
una barrera del cliente verificador; los procedimientos `013A–013D` no
necesitaron cambios.
