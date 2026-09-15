# Resultado de instalación 050A — 2026-09-15

Ámbito exclusivo: `SQL.EBIR.LOCAL\NAVISION2017 / EBIR_MES_TEST`. Ejecutado
mediante conexión integrada de PowerShell/.NET (`System.Data.SqlClient`),
autenticado como `EBIR\vjavega` (no `EBIR\MES$`), desde `MES.EBIR.LOCAL`.

- Backup `COPY_ONLY` con `CHECKSUM`, 15/09/2026 13:02:48:
  `D:\BBDD\EBIR_MES_TEST_pre050_20260915_130248.bak`. `RESTORE VERIFYONLY
  WITH CHECKSUM` correcto.
- `050A_asignacion_mesas_propia.sql` se instaló. `cfg.asignar_mesas_propias`
  existe (`OBJECT_ID = 436196604`).
- El primer ensayo falló: el contrato abre y cierra su propia transacción
  (mismo refuerzo del paquete 010, documentado en
  `010_REFUERZO_TRANSACCIONES_README.md`), así que no admite invocarse desde
  dentro de una transacción exterior ya abierta — su `ROLLBACK` ante el
  rechazo esperado 57004 revertía también los fixtures de la prueba. Se
  corrigió el ensayo (commit `d441332` / merge `7fa29b1`), no el contrato:
  los fixtures se confirman antes de invocar el procedimiento y se limpian de
  forma explícita al final, tanto si la prueba pasa como si falla.
- El ensayo repetido terminó con: "Prueba 050 correcta: seleccion propia,
  bloqueo de linea ajena, liberacion con historial y validaciones
  verificadas. Fixtures ZZ50 eliminados."
- Fixtures `ZZ50-%` en `cfg.lineas`, `seg.empleados` y asignaciones en
  `cfg.lineas_jefes`: 0 / 0 / 0.
- `DBCC CHECKDB (EBIR_MES_TEST) WITH NO_INFOMSGS`: sin errores.

`cfg.lineas_jefes` sigue vacía. El reparto real se construye cuando cada jefe
se identifica por RFID en `/dashboard` y selecciona sus mesas.
