# Paquete 027 - contexto de salida de palet por codeunit

Estado de `027A`: instalado y validado en `EBIR_MES_TEST` el 2026-08-06.

`027A_contexto_salida_palet_codeunit.sql` sustituye de forma transaccional el
procedimiento `nav.reservar_siguiente_salida_palet` sin alterar la política de
reserva, caducidad ni reintentos de 026A. El resultado reservado incorpora tres
datos autoritativos que necesita el codeunit de planta:

- lote de `prod.ordenes`;
- código NAV del empleado que cerró el palet;
- código MES de la línea de la sesión que produjo el palet.

El paquete no contacta NAV, no reencola operaciones y no modifica datos
operativos. Rechaza la instalación si existe una salida `SALIDA_PALET` en
`PROCESANDO`, comprueba todas sus dependencias y conserva el permiso exclusivo
de ejecución para `mes_runtime`.

Se validó primero dentro de una transacción exterior terminada con rollback.
Después se creó un backup `COPY_ONLY` con `CHECKSUM`, se comprobó mediante
`RESTORE VERIFYONLY` y se instaló el paquete. La definición final devuelve los
once campos esperados, conserva el permiso de `mes_runtime`, no dejó salidas en
`PROCESANDO` y `DBCC CHECKDB` terminó correctamente. La instalación no habilitó
el Worker ni realizó escrituras en NAV.
