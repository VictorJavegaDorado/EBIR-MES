# Resultado de instalación 049A — 2026-09-15

Ámbito exclusivo: `SQL.EBIR.LOCAL\NAVISION2017 / EBIR_MES_TEST`. Ejecutado
mediante conexión integrada de PowerShell/.NET, autenticado como
`EBIR\vjavega` (no `EBIR\MES$`), restringida a `EBIR_MES_TEST`.

- Backup `COPY_ONLY` con `CHECKSUM`, 15/09/2026 08:11:23:
  `D:\BBDD\EBIR_MES_TEST_pre049_20260915_081049.bak` (1.228.800 bytes físicos,
  1.213.235 bytes comprimidos registrados, `is_copy_only = True`,
  `has_backup_checksums = True`). `RESTORE VERIFYONLY WITH CHECKSUM`: "El
  conjunto de copia de seguridad del archivo 1 es válido."
- `049A_asignacion_jefes_linea.sql` se instaló atómicamente.
  `cfg.lineas_jefes` existe (`OBJECT_ID = 308196148`) y el índice único
  filtrado `UX_cfg_lineas_jefes_linea_vigente` existe.
- El primer ensayo del fixture de la comprobación "sin autor" reutilizaba una
  línea ya asignada (`linea2_id`), por lo que el índice único de vigencia se
  adelantaba al `CHECK` de autor. Se corrigió usando una tercera línea
  sintética libre (`ZZ49-L3`), commit `5da7e6c` / merge `bdcd488`.
- El ensayo repetido terminó con: "Prueba 049 correcta: dos jefes,
  reasignacion con historial y restricciones verificadas." y `ROLLBACK
  TRANSACTION`.
- Fixtures `ZZ49-%` en `cfg.lineas` y `seg.empleados`: 0. Asignaciones
  sintéticas restantes en `cfg.lineas_jefes`: 0.
- `DBCC CHECKDB (EBIR_MES_TEST) WITH NO_INFOMSGS`: finalizó correctamente,
  sin errores, mensajes ni filas de incidencias.

La tabla `cfg.lineas_jefes` queda instalada y vacía. El reparto real
jefe-línea se entrega en un paquete de datos posterior, parametrizado como el
019.
