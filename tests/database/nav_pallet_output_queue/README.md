# Validación de los paquetes 026, 027A, 028A y 029A

`verify-026-static.ps1` comprueba sin conectarse a SQL que el paquete está
restringido a `EBIR_MES_TEST`, es transaccional, procesa solo `SALIDA_PALET`,
limita reintentos y conserva `RESULTADO_DESCONOCIDO`.

`verify-026B-static.ps1` exige que la reconciliación se limite a la operación
31, preserve el intento 405, rechace cualquier identificador o reserva, sea
transaccional, registre auditoría y no contenga contacto con NAV.

La validación transaccional de 026B debe ejecutarse con rollback antes de pedir
su instalación. La instalación y el siguiente envío SOAP son fases separadas y
requieren autorización expresa.

`verify-027-static.ps1` valida sin ejecutar SQL que 027A conserva las barreras
de base y transacción y agrega lote, operario NAV y línea MES. 027A no reencola
operaciones, no crea fixtures y no contacta NAV.

`verify-028-static.ps1` exige la reserva de reconciliación por identificador
externo, el reintento de lectura sin nuevo envío, la continuidad de los palets
no finales y la barrera contra un segundo cierre mientras la salida anterior
no esté confirmada.

`verify-029-static.ps1` limita la recuperación a la operación 32 y exige la
evidencia exacta del HTTP 500 sin identificador externo, el palé 22 de 20
unidades, transacción, conservación del intento y auditoría. El paquete no
contacta NAV ni autoriza por sí mismo el siguiente envío.
