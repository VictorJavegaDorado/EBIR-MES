# Paquete 012 — ausencias, sustituciones y correcciones

Estado: **aplicado, probado y completamente validado; fixtures eliminados y
CHECKDB correcto el 29/07/2026**.

Base exclusiva: `EBIR_MES_TEST`.

## Orden de aplicación propuesto

1. `012A_iniciar_paro_operario.sql`
2. `012B_finalizar_paro_operario.sql`
3. `012C_iniciar_sustitucion_capacidad.sql`
4. `012D_finalizar_sustitucion_capacidad.sql`
5. `012E_corregir_fichaje_turno_actual.sql`
6. `012F_recursos_efectivos.sql`
7. `012G_refuerzo_entrada_productiva.sql`
8. `012H_refuerzo_salida_productiva.sql`
9. `012I_refuerzo_desbloqueo_recursos_efectivos.sql`

Los nueve archivos abortan fuera de `EBIR_MES_TEST`. El orden mantiene las
dependencias: la función común `012F` se instala antes de redefinir los tres
procedimientos que la consumen en `012G–012I`.

## Cambios estructurales

No se modifican:

- tablas;
- columnas;
- índices;
- restricciones;
- datos iniciales o productivos.

Se añade una función de tabla interna:

```text
prod.recursos_efectivos_sesion
```

La función cuenta fichajes abiertos y excluye los que tienen un paro
individual abierto. Su invocación directa se deniega a `mes_runtime`.

## Procedimientos nuevos

- `prod.iniciar_paro_operario`;
- `prod.finalizar_paro_operario`;
- `prod.iniciar_sustitucion_capacidad`;
- `prod.finalizar_sustitucion_capacidad`;
- `prod.corregir_fichaje_turno_actual`.

Si el paquete se aplica, el modelo conservará:

```text
37 tablas
16 procedimientos críticos/operativos
1 función interna del paquete 012
```

## Procedimientos redefinidos

Sin cambiar sus contratos públicos:

- `prod.registrar_entrada_productiva`;
- `prod.registrar_salida_productiva`;
- `imp.confirmar_trabajo_impresion`.

La revisión confirmó que `prod.finalizar_sesion_turno` ya:

- cierra paros abiertos;
- finaliza sustituciones activas;
- cierra fichajes como cierre de sistema;
- cierra el tramo vigente;
- libera la línea.

Por ello no necesita una nueva redefinición en este paquete.

## Flujos cubiertos

### Paro individual

- Motivos permitidos: `WC` y `PAUSA_CALOR`.
- Requiere un fichaje abierto del operario en la sesión.
- Excluye al operario de la capacidad.
- El último recurso ausente deja la sesión en `SIN_OPERARIOS`.
- El retorno es contextual y no conmuta el fichaje ordinario.

### Sustitución

- Requiere supervisor activo.
- Requiere que el operario tenga un paro abierto.
- El supervisor crea un fichaje contextual productivo.
- La sustitución restaura exactamente una plaza; no aumenta la dotación.
- El retorno del operario finaliza automáticamente la sustitución y el
  fichaje del supervisor.
- Si el supervisor finaliza antes, el paro del operario continúa y la línea
  pierde temporalmente un recurso.

### Corrección

- Solo un supervisor activo.
- Solo sobre una sesión activa.
- Motivo obligatorio.
- Rechaza fechas futuras, intervalos negativos y solapamientos.
- Rechaza una corrección que deje paros o sustituciones fuera del fichaje.
- No corrige fichajes ligados a una sustitución activa.
- Reconstruye dentro de la misma transacción los tramos de capacidad de la
  sesión desde fichajes, paros y paradas.
- Conserva en auditoría los valores anterior y nuevo.

Una corrección posterior a la sesión activa queda fuera de este contrato y
requerirá el futuro flujo administrativo de `ADMINISTRADOR_MES`.

## Estados técnicos

Las operaciones conservan los estados de línea:

```text
PENDIENTE_NAV
BLOQUEADA
```

cuando la causa técnica sigue vigente. No los sustituyen por
`PRODUCIENDO` o `SIN_OPERARIOS` únicamente por cambiar la dotación.

El desbloqueo posterior a impresión utiliza recursos efectivos:

```text
recursos efectivos > 0 → PRODUCIENDO
recursos efectivos = 0 → SIN_OPERARIOS
```

## Transacciones y concurrencia

Los procedimientos nuevos y redefinidos:

- usan `SET XACT_ABORT ON`;
- usan `TRY/CATCH`, `ROLLBACK` y `THROW`;
- utilizan hora UTC del servidor;
- bloquean el contexto antes de modificarlo;
- estabilizan fichajes, paros y sustituciones en las transiciones;
- limpian los parámetros `OUTPUT` después de un rollback cuando corresponde;
- no llaman a NAV, RFID físico ni impresoras.

Los índices filtrados existentes protegen:

- un fichaje abierto por empleado;
- un paro abierto por fichaje;
- una sustitución activa por operario;
- una sustitución activa por supervisor;
- un tramo abierto por sesión.

## Auditoría

Eventos nuevos:

- `PARO_OPERARIO_INICIADO`;
- `PARO_OPERARIO_FINALIZADO`;
- `SUSTITUCION_CAPACIDAD_INICIADA`;
- `SUSTITUCION_CAPACIDAD_FINALIZADA`;
- `SUSTITUCION_CAPACIDAD_FINALIZADA_AUTO`;
- `FICHAJE_CORREGIDO`.

No se almacenan referencias RFID. La capa SQL recibe empleados ya resueltos.

## Permisos

Los cinco procedimientos nuevos conceden únicamente `EXECUTE` a
`mes_runtime`.

Los tres procedimientos redefinidos conservan sus permisos existentes.

La función interna recibe una denegación explícita de invocación directa para
`mes_runtime`; los procedimientos del mismo propietario la consumen mediante
cadena de propiedad.

No se conceden escrituras directas, DDL, lectura de auditoría ni control de la
base.

## Revisión estática conjunta

Comprobado:

- contratos y dependencias `012A–012I`;
- códigos funcionales separados `52200–52621`;
- guardas exclusivas de base;
- una transacción, un `COMMIT` y un rollback por procedimiento;
- permisos nuevos limitados a cinco contratos;
- estados de sesión y línea;
- finalización automática y anticipada de sustituciones;
- reconstrucción transaccional de tramos;
- opciones JSON compatibles con SQL Server;
- conservación de los contratos redefinidos del paquete `011`.

## Siguiente fase

Antes de solicitar instalación:

1. preparar prevuelo y fixtures sintéticos `ZZTEST_012`; — completado
   estáticamente;
2. preparar pruebas funcionales de paros y retornos; — completado
   estáticamente;
3. preparar pruebas de sustituciones; — completado estáticamente;
4. preparar pruebas de correcciones y reconstrucción; — completado
   estáticamente;
5. preparar dos clientes de concurrencia; — completado estáticamente;
6. preparar auditoría y permisos; — completado estáticamente;
7. preparar limpieza completa y `DBCC CHECKDB`; — completado estáticamente;
8. revisar conjuntamente todo el paquete de pruebas. — completado
   estáticamente.

La revisión conjunta cubrió los nueve scripts de base `012A–012I` y los nueve
archivos de pruebas `00–07` y `99`. No se conectó a SQL Server.

Solo después se solicitarán autorizaciones separadas para instalación,
fixtures, pruebas funcionales, concurrencia, permisos y limpieza.

## Instalación autorizada

Con autorización expresa se aplicaron atómicamente `012A–012I`
exclusivamente sobre `SQL.EBIR.LOCAL\NAVISION2017` / `EBIR_MES_TEST`.

La validación posterior confirmó:

```text
37 tablas
16 procedimientos
1 función interna del paquete 012
37 registros iniciales
0 filas operativas
5 permisos EXECUTE nuevos para mes_runtime
invocación directa de la función denegada a EBIR\MES$
EBIR\MES$ continúa en mes_runtime
```

No se crearon fixtures ni se ejecutaron pruebas en esta fase.

Con una segunda autorización se ejecutó posteriormente el prevuelo y se
crearon exclusivamente los fixtures `ZZTEST_012`/`ZZ12-`: una empresa, una
impresora simulada, seis líneas, seis empleados con siete asignaciones de rol,
cuatro órdenes y cuatro formatos. No se crearon sesiones, RFID ni
dispositivos. Las pruebas `01–07` y `99` permanecen sin ejecutar.

Con una tercera autorización se ejecutaron las pruebas funcionales `01–04`.
Todas terminaron correctamente. Durante la ejecución se corrigieron tres
defectos de los propios tests: expectativas de parámetros `OUTPUT` después de
`THROW`, dos expresiones `DATEADD` usadas directamente como argumentos de
`EXEC` y el cálculo prematuro de una variable C03. Los procedimientos
operativos devolvieron los errores y estados transaccionales esperados.

El estado previo a concurrencia quedó validado con dos sesiones activas, tres
fichajes abiertos, una corrección auditada y una etiqueta simulada impresa.
El único paro abierto pertenece deliberadamente al caso de desbloqueo de L06.

Con una cuarta autorización se ejecutaron los clientes de concurrencia
`05–06` en dos conexiones independientes. La primera carrera produjo un único
ganador, pero una aserción del cliente perdedor reutilizaba el valor previo de
`@recursos`; se corrigió el centinela del test, se cerró funcionalmente la
sustitución sintética y se repitió la carrera.

La repetición terminó correctamente con un único ganador, una sustitución
activa, un único fichaje de supervisor sustituto y dos recursos efectivos. El
ganador de la repetición fue `ZZ12-SUP`.

Con una quinta autorización se ejecutó
`07_AUDITORIA_Y_PERMISOS.sql`. Los seis tipos de evento nuevos estaban
presentes y las comprobaciones efectivas de mínimo privilegio finalizaron
correctamente: cinco contratos nuevos ejecutables, función interna no
invocable directamente, auditoría no legible y ausencia de `CONTROL` sobre la
base para `EBIR\MES$`.

Con una sexta autorización se ejecutó finalmente
`99_LIMPIEZA_Y_CHECKDB.sql`. Los fixtures sintéticos se eliminaron,
las tablas operativas quedaron vacías y `DBCC CHECKDB (EBIR_MES_TEST)`
terminó sin errores.

Estado final:

```text
37 tablas
16 procedimientos
1 función interna
37 registros iniciales
0 filas operativas
0 fixtures
EBIR\MES$ miembro de mes_runtime
DBCC CHECKDB sin errores
```
