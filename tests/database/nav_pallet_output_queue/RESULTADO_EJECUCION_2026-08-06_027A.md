# Resultado de instalación 027A - 2026-08-06

Ámbito exclusivo: `SQL.EBIR.LOCAL\NAVISION2017 / EBIR_MES_TEST`.

- La validación completa dentro de una transacción exterior terminó con
  rollback y restauró el contrato 026.
- Se creó un backup `COPY_ONLY`, `CHECKSUM` y compresión, y
  `RESTORE VERIFYONLY WITH CHECKSUM` terminó correctamente.
- `027A_contexto_salida_palet_codeunit.sql` se instaló de forma atómica.
- `nav.reservar_siguiente_salida_palet` devuelve once columnas compatibles con
  el lector: contexto de operación, orden, producto, lote, operario NAV, línea
  MES, cantidad, cierre e intento.
- El permiso `EXECUTE` de `mes_runtime` quedó concedido.
- Después de la instalación había cero salidas `SALIDA_PALET` en
  `PROCESANDO`.
- `DBCC CHECKDB (EBIR_MES_TEST)` terminó sin errores.
- No se habilitó el Worker y no se contactó NAV, impresión ni RFID físico.
