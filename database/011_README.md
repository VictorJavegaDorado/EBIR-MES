# Paquete 011 — sesiones, turnos y fichajes

Estado: **aplicado y completamente validado; fixtures eliminados y CHECKDB correcto el 29/07/2026**.

Base exclusiva: `EBIR_MES_TEST`.

## Orden de aplicación propuesto

1. `011A_abrir_sesion_linea.sql`
2. `011B_registrar_entrada_productiva.sql`
3. `011C_registrar_salida_productiva.sql`
4. `011D_marcar_cambio_turno_pendiente.sql`
5. `011E_finalizar_sesion_turno.sql`
6. `011F_refuerzo_desbloqueo_impresion.sql`

Cada archivo aborta fuera de `EBIR_MES_TEST`. Los seis archivos fueron
aplicados en orden, dentro de una transacción envolvente y con autorización
expresa.

## Cambios estructurales

Ninguno:

- no crea ni altera tablas;
- no crea ni altera columnas, índices o restricciones;
- no carga configuración o datos productivos;
- no llama a NAV, RFID físico o impresoras;
- no modifica otras bases.

## Objetos añadidos

Se crearían cinco procedimientos:

- `prod.abrir_sesion_linea`;
- `prod.registrar_entrada_productiva`;
- `prod.registrar_salida_productiva`;
- `prod.marcar_cambio_turno_pendiente`;
- `prod.finalizar_sesion_turno`.

Después del paquete existirían:

```text
37 tablas
11 procedimientos críticos/operativos
```

## Objeto redefinido

`imp.confirmar_trabajo_impresion` conserva su contrato y lógica anterior. Para
un palé ordinario, después de imprimir:

```text
fichajes abiertos > 0 → PRODUCIENDO
fichajes abiertos = 0 → SIN_OPERARIOS
```

## Permisos

Cada nuevo procedimiento concede únicamente `EXECUTE` a `mes_runtime`.

No se conceden escrituras directas, lectura de auditoría, DDL ni control de la
base. `011F` no requiere una nueva concesión porque redefine un objeto que ya
conserva su permiso.

## Regla horaria confirmada

- `MANANA`: 06:00–14:00.
- `TARDE`: 14:00–22:00.
- Nueva sesión 22:00–23:59: `TARDE`, fecha actual.
- Nueva sesión 00:00–05:59: `TARDE`, fecha anterior.
- Fuera de horario: supervisor, confirmación y auditoría.
- No se crea turno nocturno.

## Invariantes protegidas

- una única sesión activa por línea;
- una FL `NORMAL` no abre dos sesiones;
- una FL `MULTILINEA` puede abrir sesiones en líneas distintas;
- un empleado no mantiene dos fichajes abiertos;
- un supervisor no entra como recurso ordinario;
- el primer fichaje crea una única primera reserva;
- volver desde `SIN_OPERARIOS` no crea otra primera reserva;
- una sesión no finaliza con reserva, NAV o impresión pendiente;
- finalizar turno no envía producción parcial a NAV;
- toda operación termina limpia tras error mediante `TRY/CATCH` y `ROLLBACK`.

## Dependencias posteriores

El paquete `012` deberá completar:

- WC y pausa de calor;
- sustitución de operario por supervisor;
- finalización automática de la sustitución al regresar el operario;
- tratamiento fino de tramos durante paradas y bloqueos;
- correcciones de fichajes durante el turno.

## Revisión estática conjunta — 29/07/2026

Se revisaron conjuntamente:

- contratos, estados y orden de bloqueos de `011A–011F`;
- `TRY/CATCH`, `ROLLBACK`, códigos funcionales y permisos;
- continuidad completa de los casos `01–45`;
- concurrencia en dos conexiones;
- auditoría y mínimo privilegio;
- limpieza inversa de dependencias y estado final esperado.

Durante la revisión se reforzaron el prevuelo, la comprobación efectiva de
permisos, el alcance exacto de la limpieza y la inicialización del parámetro
`OUTPUT` de apertura. No se conectó a SQL Server y ningún script fue ejecutado.

## Instalación autorizada — 29/07/2026

`011A–011F` se aplicó de forma atómica exclusivamente sobre
`SQL.EBIR.LOCAL\NAVISION2017` / `EBIR_MES_TEST`.

Validación posterior:

```text
37 tablas
11 procedimientos
6 contratos A–F presentes
37 registros iniciales
0 filas operativas
5 permisos EXECUTE nuevos para mes_runtime
EBIR\MES$ continúa en mes_runtime
```

Posteriormente, con autorización separada, el prevuelo confirmó el estado
limpio y se crearon los fixtures sintéticos. Las pruebas funcionales todavía
se ejecutaron en una tercera fase autorizada y terminaron correctamente.

## Criterio para solicitar aplicación

Antes de autorizar:

1. preparar fixtures `ZZTEST_011`; — completado estáticamente;
2. revisar los casos de prueba; — completado estáticamente;
3. comprobar sintaxis y dependencias sin aplicar; — completado estáticamente;
4. preparar limpieza total; — completado estáticamente;
5. fijar resultados esperados; — completado estáticamente;
6. aplicar y probar por fases con autorizaciones separadas. — completado.

## Cierre de ejecución — 29/07/2026

Las fases autorizadas de instalación, fixtures, pruebas funcionales,
concurrencia, permisos y limpieza terminaron correctamente.

Estado final de `EBIR_MES_TEST`:

```text
37 tablas
11 procedimientos
37 registros iniciales
0 filas operativas
0 fixtures
EBIR\MES$ miembro de mes_runtime
DBCC CHECKDB sin errores
```
