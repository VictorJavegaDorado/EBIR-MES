# Resultado del paquete 016 — 01/08/2026

## Alcance autorizado

Se instalo `016A_promover_ordenes_nav.sql` exclusivamente en
`SQL.EBIR.LOCAL\NAVISION2017`, base `EBIR_MES_TEST`. No se escribio en NAV, no
se promovio el snapshot real y no se modificaron IIS ni `runtime\current`.

## Proteccion y preflight

- backup `COPY_ONLY` con checksum:
  `D:\BBDD\EBIR_MES_TEST_pre016_20260801_1138.bak`;
- `RESTORE VERIFYONLY` correcto;
- ejecucion completa previa dentro de una transaccion exterior y `ROLLBACK`;
- objetos 016 confirmados dentro del preflight antes de revertirlo.

## Validacion funcional

La prueba `01_FUNCIONALES_016.sql` utilizo fixtures `ZZ16-*` y revirtio toda la
transaccion. Se validaron:

- primera promocion `CREADA`;
- repeticion de la misma correlacion recuperando `CREADA`;
- correlacion nueva e identica `SIN_CAMBIOS`;
- cambio de lote `REVISION` sin sobrescribir los datos productivos;
- creacion atomica de orden y componentes.

No quedaron residuos sinteticos. Estado final:

- 43 tablas y 23 procedimientos;
- `mes_runtime` con `EXECUTE` sobre `nav.promover_orden_entrada`;
- una orden conservada en `nav.ordenes_entrada`;
- cero filas en `nav.promociones_orden`;
- cero filas en `prod.ordenes`;
- `DBCC CHECKDB (EBIR_MES_TEST)` correcto.
