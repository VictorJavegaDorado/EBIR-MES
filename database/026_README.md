# Paquete 026 — cola segura de salidas de palet NAV

Estado: preparado; no instalado.

El paquete `026A_cola_salida_palet_nav.sql` publica el límite transaccional que
necesita un Worker para procesar exclusivamente operaciones `SALIDA_PALET`.
No contacta NAV ni contiene configuración externa.

El contrato:

- reserva una sola operación con `UPDLOCK`, `READPAST` y `ROWLOCK`;
- conserva la clave idempotente creada al cerrar el palet;
- registra cada intento en `nav.intentos_operacion`;
- limita a tres los errores reintentables;
- no reintenta automáticamente una reserva caducada: la marca como
  `RESULTADO_DESCONOCIDO`, porque NAV podría haber aceptado la salida;
- devuelve al Worker orden, producto, cantidad buena y fecha de cierre desde
  las tablas autoritativas de MES, sin confiar en datos del navegador;
- solo habilita la etiqueta mediante el contrato existente
  `nav.confirmar_salida_palet` después de recibir una confirmación inequívoca.

La instalación requiere una autorización SQL independiente y pruebas con
fixtures sintéticos en `EBIR_MES_TEST`. Instalar el paquete no habilita el
Worker ni realiza escrituras en NAV.
