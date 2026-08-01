# Pruebas de promocion de ordenes NAV (016)

`01_FUNCIONALES_016.sql` usa exclusivamente fixtures `ZZ16-*` dentro de una
transaccion exterior que siempre se revierte. Valida creacion, repeticion de
correlacion, nueva correlacion sin cambios y revision por cambio de lote. El
rechazo de reutilizacion incompatible se cubre en las pruebas del adaptador y
no se provoca dentro de la transaccion exterior porque el procedimiento debe
revertirla completa ante un error.

Precondiciones: paquete 016 instalado y ejecucion autorizada exclusivamente en
`EBIR_MES_TEST`. La prueba no consulta ni escribe en NAV y no modifica el
snapshot real conservado.
