# Diseño del paquete 011 — sesiones, turnos y fichajes

Estado: **regla horaria confirmada; implementación en preparación, no ejecutada**.

Base futura exclusiva: `EBIR_MES_TEST`.

## Objetivo

Completar el circuito anterior al paletizado:

```text
Supervisor carga/reanuda FL en línea
→ primer recurso ficha
→ comienza producción y se crea la primera reserva
→ entran/salen recursos
→ se conservan tramos de capacidad
→ supervisor finaliza la sesión de turno
```

El paquete no consultará NAV, no leerá RFID físico y no imprimirá. Recibirá
identificadores MES ya resueltos por la futura capa de aplicación.

## Procedimientos propuestos

### 1. `prod.abrir_sesion_linea`

Entradas propuestas:

```text
@orden_id
@linea_id
@formato_palet_orden_id
@supervisor_id
@inicio_fuera_horario_confirmado
@correlacion_id
@sesion_linea_id OUTPUT
```

Validaciones:

- supervisor activo;
- línea activa y en estado `LIBRE`;
- orden en estado reanudable;
- formato activo y perteneciente a la orden;
- ninguna sesión activa en la línea;
- en modo `NORMAL`, ninguna otra sesión activa para la FL;
- en modo `MULTILINEA`, permitir otras sesiones en líneas diferentes;
- fuera de 06:00–22:00 exigir confirmación del supervisor;
- no abrir sobre una línea bloqueada, pendiente NAV o fuera de servicio.

Efectos:

- determina turno y fecha operativa en horario de Madrid;
- crea `prod.sesiones_linea` con estado `CARGADA`;
- enlaza `prod.estados_linea` con estado `ORDEN_CARGADA`;
- audita `SESION_LINEA_ABIERTA`;
- no crea fichaje, tramo de capacidad ni reserva.

### 2. `prod.registrar_entrada_productiva`

Entradas propuestas:

```text
@sesion_linea_id
@empleado_id
@correlacion_id
@fichaje_id OUTPUT
@reserva_palet_id OUTPUT
```

Validaciones:

- sesión abierta y no finalizada;
- empleado activo con rol productivo `OPERARIO` o `SUPERVISOR`;
- empleado sin fichaje abierto en otra línea;
- línea en `ORDEN_CARGADA`, `PRODUCIENDO` o `SIN_OPERARIOS`;
- sin paradas incompatibles;
- el supervisor solo contará como recurso mediante el futuro flujo de
  sustitución; una entrada productiva ordinaria de supervisor se rechazará
  para no aumentar capacidad indebidamente.

Efectos:

- crea `prod.fichajes`;
- cierra el tramo de capacidad abierto, si existe;
- crea un nuevo tramo con la dotación resultante;
- con el primer recurso:
  - inicia la sesión;
  - cambia sesión y línea a `PRODUCIENDO`;
  - cambia la orden a `ABIERTA`;
  - crea automáticamente la primera reserva mediante la misma regla
    transaccional de `prod.reservar_palet`;
- audita `FICHAJE_ENTRADA_PRODUCTIVA`.

La reserva automática utiliza:

```text
min(unidades_por_palet, pendiente_disponible_global)
```

### 3. `prod.registrar_salida_productiva`

Entradas propuestas:

```text
@sesion_linea_id
@empleado_id
@correlacion_id
```

Validaciones:

- fichaje productivo abierto del empleado en esa sesión;
- ausencia de una lectura contextual distinta;
- sesión no finalizada.

Efectos:

- cierra el fichaje;
- cierra el tramo de capacidad actual;
- si quedan recursos, crea un nuevo tramo y mantiene `PRODUCIENDO`;
- si no quedan recursos, cambia sesión y línea a `SIN_OPERARIOS`;
- no cancela reservas;
- audita `FICHAJE_SALIDA_PRODUCTIVA`.

### 4. `prod.marcar_cambio_turno_pendiente`

Procedimiento técnico idempotente, invocable por el servicio:

```text
@sesion_linea_id
@correlacion_id
```

Efectos:

- marca `cambio_turno_pendiente = 1`;
- no cierra automáticamente sesión, fichajes ni reserva;
- mantiene la producción;
- audita una sola vez `CAMBIO_TURNO_PENDIENTE`.

### 5. `prod.finalizar_sesion_turno`

Entradas propuestas:

```text
@sesion_linea_id
@supervisor_id
@correlacion_id
```

Validaciones:

- supervisor activo;
- sesión abierta;
- ninguna reserva activa;
- ninguna operación NAV/impresión de la línea bloqueando el cierre;
- si existe una reserva, el procedimiento rechaza: debe cerrarse o cancelarse
  previamente con motivo.

Efectos:

- cierra fichajes abiertos como cierre de sistema;
- cierra paros individuales y tramos abiertos;
- finaliza la sesión como `FINALIZADA_TURNO`;
- deja la orden `ABIERTA` o `PICO_PENDIENTE`, según su estado previo;
- libera `prod.estados_linea` a `LIBRE`, sin sesión;
- audita `SESION_FINALIZADA_TURNO`;
- no envía salida parcial a NAV.

### 6. Refuerzo de desbloqueo después de impresión

La implementación actual de `imp.confirmar_trabajo_impresion` devuelve un
palé ordinario a `PRODUCIENDO` después de imprimir. Al introducir fichajes
reales puede ocurrir que el último recurso haya salido mientras la línea estaba
`PENDIENTE_NAV`.

El paquete `011` deberá reforzar ese desbloqueo:

```text
si quedan fichajes abiertos  → línea PRODUCIENDO
si no quedan fichajes        → línea SIN_OPERARIOS
```

La sesión debe quedar en el mismo estado. No se impedirá que un operario salga
por estar pendiente NAV o impresión.

## Concurrencia y transacciones

Los cinco procedimientos:

- usarán `SET XACT_ABORT ON`;
- utilizarán `TRY/CATCH`, `ROLLBACK` y `THROW`;
- bloquearán orden, sesión, línea y fichajes en orden estable;
- conservarán los códigos de error funcionales;
- terminarán con `@@TRANCOUNT = 0` cuando se invoquen autónomamente;
- no emitirán efectos externos dentro de la transacción.

## Pruebas mínimas del paquete

1. Abrir sesión normal en línea libre.
2. Rechazar segunda sesión activa en la misma línea.
3. Rechazar segunda línea para FL en modo `NORMAL`.
4. Permitir segunda línea para FL `MULTILINEA`.
5. Primer fichaje inicia producción y primera reserva.
6. Segundo operario crea nuevo tramo de capacidad.
7. Un empleado no puede fichar en dos líneas.
8. Salida de un recurso reduce capacidad.
9. Salida del último recurso deja `SIN_OPERARIOS`.
10. Doble lectura controlada no duplica fichaje.
11. Cambio de turno pendiente no cierra la sesión.
12. Fin de turno rechazado con reserva activa.
13. Cancelar reserva y finalizar sesión.
14. Cerrar fichajes y tramos al finalizar.
15. Auditoría, permisos, limpieza y `DBCC CHECKDB`.
16. Último operario sale durante `PENDIENTE_NAV`; la impresión desbloquea a
    `SIN_OPERARIOS`, no a `PRODUCIENDO`.

## Decisión horaria confirmada

Turnos confirmados:

```text
MANANA: 06:00–14:00
TARDE:  14:00–22:00, con extensión
```

Está confirmado que una sesión de tarde ya abierta puede continuar después de
las 22:00. Para una **sesión nueva** autorizada fuera de horario se aplicará:

- De 22:00 a 23:59: turno `TARDE`, fecha operativa del día actual.
- De 00:00 a 05:59: turno `TARDE`, fecha operativa del día anterior.
- Exigir siempre supervisor y confirmación explícita.
- Auditar `INICIO_FUERA_HORARIO`.
- No crear un turno nocturno.

Esta regla mantiene una única extensión continua del turno de tarde y evita
inventar un tercer turno.
