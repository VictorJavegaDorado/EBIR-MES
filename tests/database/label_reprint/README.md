# Pruebas de reimpresion de etiqueta de palet

`01_FUNCIONALES_038.sql` crea fixtures `ZZ38-*` dentro de una transaccion
exterior, solicita dos veces la misma correlacion, reserva el unico trabajo con
el contrato del Worker y lo completa con datos tecnicos simulados. Verifica que
la etiqueta original y la linea no cambian y revierte todos los datos.

No ejecutar sin autorizacion expresa sobre `EBIR_MES_TEST`. La prueba no llama
a NAV ni a una impresora: los fixtures no se confirman fuera de la transaccion
exterior y el adaptador fisico no participa.
