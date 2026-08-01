# Paquete 018 — cola segura de impresión

Estado: preparado para validación e instalación controlada en `EBIR_MES_TEST`.

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
