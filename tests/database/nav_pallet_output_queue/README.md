# Validación de los paquetes 026A y 026B

`verify-026-static.ps1` comprueba sin conectarse a SQL que el paquete está
restringido a `EBIR_MES_TEST`, es transaccional, procesa solo `SALIDA_PALET`,
limita reintentos y conserva `RESULTADO_DESCONOCIDO`.

`verify-026B-static.ps1` exige que la reconciliación se limite a la operación
31, preserve el intento 405, rechace cualquier identificador o reserva, sea
transaccional, registre auditoría y no contenga contacto con NAV.

La validación transaccional de 026B debe ejecutarse con rollback antes de pedir
su instalación. La instalación y el siguiente envío SOAP son fases separadas y
requieren autorización expresa.
