# Resultado de ejecucion del paquete 022

Fecha: 05/08/2026.

Destino exclusivo: `SQL.EBIR.LOCAL\NAVISION2017`, base `EBIR_MES_TEST`.

## Validacion previa

- Precondiciones 003, 015, 016, 017 y 021 presentes.
- Objetos 022 ausentes antes del ensayo.
- Paquete completo ejecutado dentro de una transaccion exterior.
- Tabla, procedimiento, promocion y permiso visibles dentro del ensayo.
- Rollback exterior correcto; tabla y procedimiento volvieron a quedar ausentes.

## Copia e instalacion

- Backup `COPY_ONLY` con checksum:
  `D:\BBDD\EBIR_MES_TEST_pre022_20260805_104355_360e0ac3.bak`.
- `RESTORE VERIFYONLY` correcto.
- Instalacion definitiva correcta.
- `nav.formatos_palet_orden_entrada`: 8 columnas y 4 restricciones `CHECK`.
- `nav.registrar_formato_palet_snapshot_orden`: presente.
- `nav.promover_orden_entrada_con_lote_nav`: promocion POK incorporada.
- Dos permisos `EXECUTE` requeridos concedidos a `mes_runtime`.
- La nueva bandeja termino con cero filas; no se usaron fixtures ni datos NAV.

## Integridad y alcance

- `DBCC CHECKDB (EBIR_MES_TEST) WITH NO_INFOMSGS`: correcto.
- No se escribio en NAV ni se consulto otra base.
- No se cambio IIS ni se activo una release.
