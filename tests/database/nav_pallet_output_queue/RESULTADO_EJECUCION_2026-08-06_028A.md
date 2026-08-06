# Resultado de instalación 028A — 2026-08-06

Ámbito exclusivo: `SQL.EBIR.LOCAL\NAVISION2017 / EBIR_MES_TEST`.

- La validación completa se ejecutó dentro de una transacción exterior y
  terminó con rollback.
- Se creó un backup `COPY_ONLY`, `CHECKSUM` y compresión, y
  `RESTORE VERIFYONLY WITH CHECKSUM` terminó correctamente.
- `028A_reconciliacion_salida_palet_continua.sql` se instaló atómicamente.
- La reserva devuelve doce columnas e incluye el identificador externo que
  activa el modo de reconciliación sin repetir la escritura NAV.
- La operación de ensayo 31 conservó `RESULTADO_DESCONOCIDO`; no se reencoló ni
  se contactó NAV.
- La línea de `FL26-00003` pasó de `PENDIENTE_NAV` a `SIN_OPERARIOS`, sin
  alterar la salida ni la etiqueta pendientes.
- Cero operaciones `SALIDA_PALET` quedaron en `PROCESANDO`.
- `DBCC CHECKDB (EBIR_MES_TEST)` terminó sin errores.
- Worker, impresión y RFID físico permanecieron desactivados.
