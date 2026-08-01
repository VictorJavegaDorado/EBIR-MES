# Paquete 018 — cola segura de impresión

Estado: instalado y validado en `EBIR_MES_TEST` el 01/08/2026.

El paquete convierte la cola ya existente en un contrato consumible por el
worker sin conceder escrituras directas. Añade metadatos de reserva y reintento
a `imp.trabajos_impresion` y publica tres procedimientos:

- `imp.reservar_siguiente_trabajo_impresion` reserva atómicamente con
  `UPDLOCK`, `READPAST` y `ROWLOCK`;
- `imp.completar_trabajo_impresion` confirma la impresión mediante el contrato
  funcional existente y registra el intento;
- `imp.fallar_trabajo_impresion` registra un fallo, reintenta como máximo tres
  veces y termina en `ERROR`.

Una reserva que supera cinco minutos no se reimprime automáticamente: pasa a
`RESULTADO_DESCONOCIDO`, porque el equipo podría haber impreso antes de perder
la respuesta. Esta decisión evita duplicados físicos silenciosos.

Los únicos permisos nuevos para `mes_runtime` son `EXECUTE` sobre estos tres
procedimientos. El paquete no configura impresoras, no contiene direcciones de
red y no contacta hardware.

El worker permanece deshabilitado por defecto. En modo `Simulated` escribe un
recibo JSON determinista por trabajo; el recibo incluye los datos de etiqueta,
incluido el lote procedente de NAV.

La instalación se realizó después de un prevuelo con rollback y del backup
`D:\BBDD\EBIR_MES_TEST_pre018_20260801_1345.bak`, verificado con
`RESTORE VERIFYONLY`. La prueba funcional transaccional y `DBCC CHECKDB`
terminaron correctamente.

Después se ejecutó un ciclo real del worker como `NT AUTHORITY\Servicio de red`:
reservó un trabajo sintético, generó un recibo con lote `FL2002277`, confirmó
los estados `COMPLETADO` e `IMPRESA` y registró un intento. Los fixtures se
eliminaron al finalizar. Evidencia operativa:
`C:\MES\runtime\shared\logs\manual-simulated-print-20260801-c1cdcb1.json`.
