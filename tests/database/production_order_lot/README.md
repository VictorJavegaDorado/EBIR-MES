# Pruebas del lote NAV de ordenes (017)

`01_FUNCIONALES_017.sql` usa fixtures `ZZ17-*` dentro de una transaccion que
siempre se revierte. Valida el registro del lote ligado al hash del snapshot,
la promocion sin parametros manuales de lote y la repeticion idempotente.

Precondiciones: paquete 017 instalado y ejecucion autorizada exclusivamente en
`EBIR_MES_TEST`. La prueba no consulta ni escribe en NAV.

`verify-017-static.ps1` revisa localmente los controles estructurales del
paquete sin conectarse a SQL Server.
