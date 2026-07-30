# Diseño del paquete 012 — ausencias, sustituciones y correcciones

Estado: **diseño estático inicial; `012A–012I` preparados y no ejecutados**.

Base futura exclusiva: `EBIR_MES_TEST`.

## Objetivo

Completar el circuito productivo posterior al paquete `011`:

```text
Operario activo
→ inicia WC o pausa de calor
→ queda temporalmente fuera de capacidad
→ opcionalmente un supervisor lo sustituye sin aumentar la dotación
→ el operario regresa o el supervisor termina antes la sustitución
→ se conserva cada intervalo real de capacidad
→ un supervisor puede corregir un fichaje del turno actual con auditoría
```

El paquete no consultará NAV, no leerá RFID físico y no accederá a impresoras.
Recibirá identificadores MES ya resueltos por la futura capa de aplicación.

## Alcance estructural

El modelo vigente ya contiene:

- `prod.fichajes`;
- `prod.paros_operario`;
- `prod.sustituciones_capacidad`;
- `prod.tramos_capacidad`;
- `prod.paradas_linea`;
- `prod.sesiones_linea`;
- `prod.estados_linea`.

La propuesta no necesita tablas, columnas, índices, restricciones ni datos
iniciales nuevos. Añade una función interna,
`prod.recursos_efectivos_sesion`, para que todos los procedimientos utilicen
la misma definición de capacidad. Su invocación directa queda denegada a
`mes_runtime`; los procedimientos la consumirán mediante cadena de propiedad.

## Regla única de recursos efectivos

Toda transición de capacidad debe utilizar la misma definición:

```text
recursos efectivos =
fichajes abiertos de la sesión
que no tienen un paro individual abierto
```

Durante una sustitución:

- el fichaje del operario sustituido permanece abierto;
- su paro individual permanece abierto y lo excluye de la capacidad;
- se crea un fichaje productivo para el supervisor sustituto;
- el supervisor cuenta como un recurso;
- la dotación total no aumenta respecto del instante anterior al paro.

La sustitución no debe descontar por segunda vez al operario ausente. Su
exclusión ya procede del paro abierto.

Si la sesión o la línea se encuentran en una parada que detiene la producción,
pueden existir recursos efectivos asociados, pero no se abre un tramo
productivo hasta que la parada termine.

## Regla común de transición de capacidad

Las operaciones del paquete deben aplicar atómicamente esta secuencia:

1. bloquear orden, sesión, línea, fichajes, paros, sustituciones y tramo en un
   orden estable;
2. validar la acción contextual;
3. cerrar el tramo productivo abierto en la hora del servidor;
4. aplicar la entrada, salida, paro, retorno o sustitución;
5. recalcular los recursos efectivos;
6. abrir un nuevo tramo solo si la producción puede continuar y existen
   recursos efectivos;
7. actualizar sesión y línea a `PRODUCIENDO` o `SIN_OPERARIOS`, salvo que la
   línea conserve legítimamente `PENDIENTE_NAV`, `BLOQUEADA` o `STANDBY`;
8. auditar la acción;
9. confirmar la transacción.

Cada tramo cerrado conservará:

```text
segundos_productivos = DATEDIFF(SECOND, inicio_utc, fin_utc)
```

No se crearán tramos de duración cero duplicados para una misma transición.

## Procedimientos propuestos

### 1. `prod.iniciar_paro_operario`

Entradas:

```text
@sesion_linea_id
@empleado_id
@motivo                 -- WC o PAUSA_CALOR
@correlacion_id
@paro_operario_id OUTPUT
@recursos_activos OUTPUT
```

Validaciones:

- correlación obligatoria;
- sesión activa;
- empleado activo con rol `OPERARIO`;
- fichaje productivo abierto en esa sesión;
- motivo incluido en `WC` o `PAUSA_CALOR`;
- ausencia de otro paro abierto para el fichaje;
- el empleado no actúa como supervisor sustituto;
- línea y sesión en un estado compatible.

Efectos:

- crea el paro individual;
- cierra el tramo de capacidad vigente;
- recalcula recursos;
- si quedan recursos, abre un tramo `PARO_WC` o `PARO_PAUSA_CALOR`;
- si no quedan recursos, no abre tramo y deja sesión y línea en
  `SIN_OPERARIOS`;
- audita `PARO_OPERARIO_INICIADO`.

### 2. `prod.finalizar_paro_operario`

Entradas:

```text
@sesion_linea_id
@empleado_id
@correlacion_id
@paro_operario_id OUTPUT
@sustitucion_finalizada_id OUTPUT
@recursos_activos OUTPUT
```

Validaciones:

- sesión activa;
- fichaje productivo abierto;
- exactamente un paro individual abierto;
- línea y sesión en un estado compatible.

Efectos:

- cierra el paro;
- si el operario tiene una sustitución activa:
  - finaliza automáticamente la sustitución;
  - cierra como cierre de sistema el fichaje del supervisor sustituto;
  - audita la finalización automática;
- cierra el tramo vigente, si existe;
- recalcula recursos y abre `RETORNO_WC` o `RETORNO_PAUSA_CALOR`;
- devuelve sesión y línea a `PRODUCIENDO` cuando corresponda;
- audita `PARO_OPERARIO_FINALIZADO`.

El retorno es una lectura contextual y no debe conmutar ni cerrar el fichaje
productivo ordinario del operario.

### 3. `prod.iniciar_sustitucion_capacidad`

Entradas:

```text
@sesion_linea_id
@operario_sustituido_id
@supervisor_sustituto_id
@motivo
@correlacion_id
@sustitucion_capacidad_id OUTPUT
@fichaje_supervisor_id OUTPUT
@recursos_activos OUTPUT
```

Validaciones:

- supervisor sustituto activo y con rol `SUPERVISOR`;
- operario sustituido activo y con rol `OPERARIO`;
- ambos empleados distintos;
- fichaje abierto del operario en la sesión;
- paro individual abierto del operario;
- ninguna sustitución activa para ese operario;
- el supervisor no tiene otro fichaje abierto ni otra sustitución activa;
- sesión y línea activas y compatibles;
- motivo no vacío.

Efectos:

- crea un fichaje productivo del supervisor;
- crea la sustitución enlazando ambos fichajes;
- cierra el tramo vigente y abre otro con exactamente un recurso efectivo más,
  restaurando la plaza temporalmente cubierta;
- audita `SUSTITUCION_CAPACIDAD_INICIADA`.

La operación no incorpora una plaza adicional: cubre únicamente la del
operario ausente seleccionado.

### 4. `prod.finalizar_sustitucion_capacidad`

Entradas:

```text
@sustitucion_capacidad_id
@supervisor_id
@motivo
@correlacion_id
@recursos_activos OUTPUT
```

Validaciones:

- sustitución activa;
- el autorizador es el propio supervisor sustituto o un supervisor activo;
- motivo no vacío;
- sesión todavía activa.

Efectos:

- finaliza la sustitución;
- cierra el fichaje del supervisor sustituto como cierre de sistema;
- mantiene abierto el paro y el fichaje del operario sustituido;
- cierra el tramo vigente;
- abre otro con un recurso menos o deja `SIN_OPERARIOS`;
- audita `SUSTITUCION_CAPACIDAD_FINALIZADA`.

Si después regresa el operario, `prod.finalizar_paro_operario` lo reincorpora
sin intentar finalizar de nuevo la sustitución.

### 5. `prod.corregir_fichaje_turno_actual`

Entradas:

```text
@fichaje_id
@entrada_utc_corregida
@salida_utc_corregida
@supervisor_id
@motivo
@correlacion_id
```

Alcance inicial:

- únicamente fichajes de una sesión activa del turno actual;
- únicamente supervisor activo;
- motivo obligatorio;
- no crea ni elimina empleados, sesiones o fichajes;
- no corrige fichajes vinculados a una sustitución activa;
- no permite intervalos negativos ni solapamiento productivo del empleado con
  otra sesión;
- no permite mover el fichaje fuera de los límites temporales de la sesión;
- una corrección posterior al turno queda fuera de este procedimiento y
  requerirá el futuro flujo de `ADMINISTRADOR_MES`.

Efectos:

- conserva en auditoría los valores anterior y nuevo;
- actualiza las horas y marca el fichaje como `CORREGIDO`;
- informa `corregido_por_empleado_id` y `motivo_correccion`;
- reconstruye de forma determinista los tramos afectados de la sesión usando
  fichajes, paros, sustituciones y paradas como fuentes temporales;
- audita `FICHAJE_CORREGIDO`.

La reconstrucción de tramos será una rutina interna común y no quedará
expuesta a `mes_runtime` como operación libre.

## Ajustes a procedimientos del paquete 011

Para que todos los caminos utilicen la misma semántica de capacidad, el
paquete `012` deberá redefinir mínimamente:

- `prod.registrar_entrada_productiva`;
- `prod.registrar_salida_productiva`;
- `imp.confirmar_trabajo_impresion`.

Los contratos públicos se conservarán siempre que sea posible.

Los ajustes previstos son:

- calcular recursos efectivos descontando paros abiertos;
- impedir que una lectura ordinaria sustituya una lectura contextual;
- cerrar de forma coherente paros y sustituciones al finalizar turno;
- utilizar la misma rutina de transición de tramos;
- conservar el orden global de bloqueos establecido en `011`.

La revisión conjunta confirmó que `prod.finalizar_sesion_turno` ya cierra
paros, sustituciones, fichajes y tramo de forma coherente, por lo que no
necesita redefinición adicional.

`012G_refuerzo_entrada_productiva.sql` conserva el contrato público de
`prod.registrar_entrada_productiva` y sustituye el recuento bruto de fichajes
por la función común de recursos efectivos.

`012H_refuerzo_salida_productiva.sql` conserva el contrato público de
`prod.registrar_salida_productiva` y aplica la misma definición después de
cerrar el fichaje.

`012I_refuerzo_desbloqueo_recursos_efectivos.sql` redefine sin cambiar su
contrato `imp.confirmar_trabajo_impresion`: después de un palé ordinario,
`PRODUCIENDO` exige al menos un recurso efectivo, no solo un fichaje abierto.

## Concurrencia y transacciones

Todos los procedimientos:

- usarán `SET XACT_ABORT ON`;
- utilizarán `TRY/CATCH`, `ROLLBACK` y `THROW`;
- emplearán hora UTC del servidor con `datetime2(3)`;
- bloquearán en orden estable;
- revalidarán roles y estado dentro de la transacción;
- no llamarán a sistemas externos;
- terminarán con `@@TRANCOUNT = 0` y `XACT_STATE() = 0` cuando fallen de forma
  autónoma;
- concederán únicamente `EXECUTE` a `mes_runtime`.

## Casos mínimos de prueba

1. Iniciar y finalizar WC con varios operarios.
2. Iniciar y finalizar pausa de calor.
3. Rechazar motivo no permitido.
4. Rechazar doble paro.
5. El último recurso en paro deja `SIN_OPERARIOS`.
6. El retorno del primer recurso reabre producción.
7. Iniciar sustitución sin aumentar la dotación.
8. Rechazar sustitución sin paro abierto.
9. Rechazar supervisor ya activo en otra línea.
10. Retorno del operario finaliza automáticamente la sustitución.
11. La finalización anticipada del supervisor reduce un recurso.
12. El retorno posterior del operario recupera ese recurso.
13. Dos clientes no pueden sustituir simultáneamente al mismo operario.
14. Un supervisor no puede sustituir simultáneamente en dos líneas.
15. Corregir fichaje de la sesión y turno actuales.
16. Rechazar corrección sin motivo.
17. Rechazar corrección que solape otro fichaje.
18. Rechazar corrección de una sesión finalizada.
19. Reconstruir tramos sin huecos ni solapamientos.
20. Mantener `PENDIENTE_NAV`, `BLOQUEADA` y `STANDBY` cuando corresponda.
21. Finalizar turno con paros y sustituciones abiertos.
22. Verificar auditoría, mínimo privilegio y ausencia de referencias RFID.
23. Limpiar todos los fixtures y ejecutar `DBCC CHECKDB`.

## Orden de preparación propuesto

1. cerrar la especificación de reconstrucción de tramos;
2. redactar los procedimientos `012A–012E`; — completado estáticamente;
3. redactar los refuerzos comunes sobre `011`;
4. preparar fixtures y pruebas funcionales;
5. preparar clientes de concurrencia;
6. preparar auditoría, permisos y limpieza;
7. revisar estáticamente el paquete completo;
8. solicitar autorizaciones separadas para instalación y cada fase de prueba.

Hasta recibir esas autorizaciones no se ejecutará SQL.
