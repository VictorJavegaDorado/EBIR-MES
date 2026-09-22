# Paquete 051 - Confirmación tardía de la salida 26926

`051A_confirmar_reconciliacion_tardia_salida_palet_122.sql` confirma en MES la
operación 122 después de verificar externamente que NAV registró la salida
26926 sin duplicados.

El paquete no contacta NAV, no contabiliza fabricación ni consumo y no amplía
la ventana de reintentos. Exige el estado exacto de la orden `FL26-00023`, el
palé 111, sus 24 intentos agotados, la etiqueta 113 todavía bloqueada y una
única impresora principal activa. Dentro de una transacción bloquea y repite
todas las comprobaciones antes de utilizar `nav.confirmar_salida_palet`.

El resultado esperado es una operación `CONFIRMADA`, la etiqueta original en
`LISTA` y un único trabajo de impresión `PENDIENTE`. El Worker MES es quien
entrega posteriormente esa etiqueta a la Vretti.

La instalación está permitida únicamente en `EBIR_MES_TEST` y requiere backup
`COPY_ONLY`, ensayo transaccional y autorización expresa.
