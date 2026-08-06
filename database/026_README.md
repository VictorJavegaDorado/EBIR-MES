# Paquete 026 — cola segura de salidas de palet NAV

Estado de `026A`: instalado en `EBIR_MES_TEST` el 2026-08-06.

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

## Reconciliación 026B

El primer ensayo controlado demostró que la página ODataV4 publicada permite
lectura pero rechaza `POST` con HTTP 405. La operación 31 quedó en
`ERROR_DEFINITIVO`, sin identificador externo y con un único intento auditado.

`026B_reencolar_salida_palet_405.sql` queda preparado, pero no instalado. Solo
puede reencolar esa operación si conserva exactamente el rechazo 405, no tiene
reserva ni identificador externo y el palet de `FL26-00003` continúa cerrado.
Mantiene el intento 1, de modo que el envío SOAP será el intento 2, y registra
la decisión en `aud.eventos`. No contiene endpoint ni contacta NAV.
