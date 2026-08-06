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

`026B_reencolar_salida_palet_405.sql` se validó transaccionalmente y se instaló
en `EBIR_MES_TEST` el 2026-08-06 tras un backup `COPY_ONLY` verificado. Solo
reencoló esa operación después de comprobar el rechazo 405, la ausencia de
reserva e identificador externo y que el palet de `FL26-00003` continuaba
cerrado. Conservó el intento 1 y registró la decisión en `aud.eventos`.

El intento 2 usó SOAP, pero recibió HTTP 500 porque el WSDL publicado en ese
momento no exponía `Create`. MES lo clasificó como
`RESULTADO_DESCONOCIDO`, sin identificador externo. La reconciliación OData
posterior devolvió cero filas.

## Reconciliación 026C

Después de corregir y compilar la página NAV TEST 50036, el WSDL pasó a exponer
`Create` y `CreateMultiple`, sin publicar `Update` ni `Delete`.
`026C_reencolar_salida_palet_wsdl.sql` se validó transaccionalmente y se instaló
en `EBIR_MES_TEST` el 2026-08-06 tras un backup `COPY_ONLY` verificado. Exigió
exactamente los dos intentos anteriores y la primera decisión de reencolación;
registró la segunda decisión en auditoría y no contactó NAV.

El intento 3 recibió HTTP 200 y NAV devolvió un identificador positivo, los
datos esperados y estado `Pendiente`. Por contrato MES conserva el identificador
y deja la operación en `RESULTADO_DESCONOCIDO`: tres intentos registrados,
reserva liberada, etiqueta no habilitada y cero trabajos de impresión. La
reconciliación OData de solo lectura encontró exactamente una fila para
`FL26-00003` / `27920LG`, cantidad 20, tipo `Salida` y estado `Pendiente`.

No se autoriza otra alta ni una nueva reencolación: la fila ya existe en NAV.
Queda pendiente definir y autorizar el paso de reconciliación que confirmará la
operación local únicamente cuando NAV publique un estado inequívoco.

El sucesor `027A`, instalado el 2026-08-06, no modifica ese historial ni
reencola la operación 31. Únicamente amplía la reserva futura con el contexto
necesario para invocar el codeunit de planta.
