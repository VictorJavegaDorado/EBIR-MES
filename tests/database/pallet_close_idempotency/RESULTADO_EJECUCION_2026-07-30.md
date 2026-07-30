# Resultado de ejecución del paquete 014 — 30/07/2026

Destino exclusivo:

```text
SQL.EBIR.LOCAL\NAVISION2017
EBIR_MES_TEST
```

No se consultó ni utilizó ninguna otra base. No se llamó a NAV, RFID físico,
dispositivos ni impresoras. No se modificó IIS.

## Revisión previa

El repositorio estaba limpio y sincronizado en:

```text
f3ac0ee4722253a003f83849050ae4345030631d
test: harden pallet close SQL authorization phases
```

`HEAD`, `origin/main` y GitHub coincidían. La revisión estática del instalador y
de las siete fases de prueba terminó correctamente.

## Instalación

`014A_cerrar_palet_idempotente.sql` se instaló dentro de su transacción
atómica.

SHA-256 del archivo ejecutado:

```text
9F204AEF4519BD310BF44766404D6E84AD155B7968486DBA59DFB8833BA9EFD1
```

Validación posterior:

- `prod.cerrar_palet_idempotente` existe;
- la definición contiene `sp_getapplock` y delega en `prod.cerrar_palet`;
- `mes_runtime` tiene `EXECUTE` directo sobre el contrato nuevo;
- `mes_runtime` ya no conserva `EXECUTE` directo sobre el contrato anterior.

## Fixtures

`00_PREVUELO_Y_FIXTURES_014.sql` terminó correctamente y creó:

```text
1 empresa NAV sintética
3 líneas
3 empleados
2 órdenes
2 formatos
3 sesiones
3 estados de línea
```

## Pruebas funcionales

`01_FUNCIONALES_014.sql` terminó correctamente.

Se confirmó:

- misma correlación y mismos parámetros devuelven el mismo `palet_id`;
- existe un solo palé, una operación NAV local, una etiqueta y un evento de
  cierre;
- parámetros diferentes reutilizando correlación reciben `55403` sin filas
  parciales ni transacciones abiertas;
- una correlación de otra operación recibe `55402`;
- una correlación nula recibe `55400`;
- el rechazo productivo representativo `51400` se conserva;
- quedaron exactamente dos reservas activas para la concurrencia.

## Concurrencia

`05_CONCURRENCIA_A_014.sql` y `06_CONCURRENCIA_B_014.sql` se ejecutaron en dos
conexiones independientes con esta marca UTC común, sustituida únicamente en
memoria:

```text
2026-07-30T14:37:36.669Z
```

Duraciones completas observadas:

```text
cliente A: 19.402 ms
cliente B: 19.360 ms
```

Resultados:

- el replay concurrente devolvió el mismo palé 9 a ambos clientes;
- hubo un único palé, operación NAV local, etiqueta y evento de cierre para la
  correlación compartida;
- la carrera con correlaciones diferentes dejó un ganador, palé 10;
- el cliente perdedor recibió exactamente `51403`;
- se reunieron las cuatro barreras de auditoría;
- las dos aserciones temporales de B demostraron una espera mínima de
  2.000 ms;
- al terminar había 0 sesiones, 0 transacciones, 0 bloqueos y 0 esperas de los
  clientes A/B.

Una primera consulta diagnóstica contó seis bloqueos porque su patrón incluía
la propia conexión de revisión. Se detuvo el avance, se corrigió el filtro para
usar exclusivamente los nombres exactos de A y B, y las cuatro métricas
resultaron cero.

## Permisos efectivos

`07_PERMISOS_014.sql` confirmó que `EBIR\MES$`:

- puede ejecutar `prod.cerrar_palet_idempotente`;
- no puede ejecutar directamente `prod.cerrar_palet`;
- no puede insertar directamente en `prod.palets`, `nav.operaciones` ni
  `imp.etiquetas`.

## Limpieza e integridad

`99A_LIMPIEZA_014.sql` eliminó exclusivamente los fixtures
`ZZTEST_014` / `ZZ14-`.

La verificación posterior encontró:

```text
0 empresas sintéticas
0 líneas sintéticas
0 empleados sintéticos
0 órdenes sintéticas
0 auditorías con correlaciones del paquete
0 transacciones de los clientes A/B
```

`99B_DBCC_014.sql` terminó en 1.026 ms. `DBCC CHECKDB` no encontró errores.

## Validación de aplicación

Después de completar SQL:

```text
dotnet format: correcto
build Release: 0 errores y 0 advertencias
pruebas .NET: 428 correctas
TypeScript: correcto
build frontend: correcto
pruebas frontend: 4 correctas
estructura: correcta
revisión estática 014: correcta
git diff --check: correcto
```
