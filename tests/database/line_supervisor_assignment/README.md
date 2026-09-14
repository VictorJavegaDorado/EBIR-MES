# Pruebas de asignacion de jefes de linea

`01_FUNCIONALES_049.sql` crea fixtures `ZZ49-*` dentro de una transaccion
exterior: dos lineas y dos supervisores sinteticos. Comprueba que un jefe puede
tener varias lineas, que una linea rechaza dos jefes vigentes, que cerrar la
vigencia permite reasignar conservando el historial, que la vigencia invertida
y la falta de autor se rechazan, y que la consulta del panel resuelve el jefe
vigente. Termina siempre con `ROLLBACK`.

La prueba usa `XACT_ABORT OFF` para capturar las violaciones de restriccion
esperadas sin condenar la transaccion exterior.

No ejecutar sin autorizacion expresa sobre `EBIR_MES_TEST`. No contacta NAV,
RFID ni impresoras.
