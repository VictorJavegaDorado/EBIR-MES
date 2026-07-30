# Resultado de ejecución del paquete 013 — 29/07/2026

Destino exclusivo:

```text
SQL.EBIR.LOCAL\NAVISION2017
EBIR_MES_TEST
```

No se consultó ni utilizó ninguna otra base. No se llamó a NAV, RFID,
dispositivos o impresoras.

## Instalación

`013A–013D` se instalaron atómicamente en una única transacción.

Validación:

```text
37 tablas
20 procedimientos
1 función interna
4 permisos EXECUTE nuevos para mes_runtime
37 registros iniciales
0 filas operativas antes de fixtures
```

## Fixtures

`00_PREVUELO_Y_FIXTURES_013.sql` terminó correctamente y creó:

```text
1 empresa NAV sintética
4 líneas y 4 estados de línea
7 empleados
6 asignaciones de rol
3 órdenes
3 formatos
6 componentes
0 RFID
0 dispositivos
0 impresoras
0 sesiones iniciales
```

## Pruebas funcionales

`01–04` terminaron correctamente a la primera.

Se validaron altas y revisiones de scrap, deltas, anulaciones, operaciones NAV
locales, solicitudes, máquina de estados, asignación, idempotencia, auditoría
y estados transaccionales limpios.

## Concurrencia

`05` y `06` se ejecutaron en conexiones independientes con una única marca UTC
común sustituida solo en memoria.

El primer intento descubrió que el cliente B podía alcanzar su comprobación
global inmediatamente antes de que el cliente A confirmara la última revisión.
Los procedimientos habían serializado correctamente; el defecto pertenecía a
la aserción temporal del test.

Se añadió:

- una barrera final acotada en `06`;
- una guarda reanudable en `05`.

La repetición completó correctamente las cinco carreras:

- dos revisiones serializadas y numeradas;
- aceptación única;
- aceptación frente a rechazo;
- entrega frente a cancelación;
- revisión frente a solicitud vinculada.

No fue necesario modificar ningún procedimiento `013`.

## Auditoría y permisos

`07_AUDITORIA_Y_PERMISOS.sql` confirmó:

- los nueve tipos de evento `013`;
- autor, rol, contexto, correlación y valores JSON;
- motivos obligatorios;
- ausencia de RFID y secretos;
- ejecución positiva de `013A–013D` para `EBIR\MES$`;
- lectura funcional;
- ausencia de DML directo, auditoría, DDL, `ALTER` y `CONTROL`.

## Limpieza e integridad

`99_LIMPIEZA_Y_CHECKDB.sql` eliminó exclusivamente los fixtures
`ZZTEST_013`/`ZZ13-`.

Estado final comprobado de forma independiente:

```text
base actual: EBIR_MES_TEST
37 tablas
20 procedimientos
1 función interna
37 registros iniciales
0 filas operativas
0 fixtures
EBIR\MES$ miembro de mes_runtime
DBCC CHECKDB sin errores
```

