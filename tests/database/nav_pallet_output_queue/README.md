# Validación del paquete 026A

`verify-026-static.ps1` comprueba sin conectarse a SQL que el paquete está
restringido a `EBIR_MES_TEST`, es transaccional, procesa solo `SALIDA_PALET`,
limita reintentos y conserva `RESULTADO_DESCONOCIDO`.

Las pruebas funcionales y de concurrencia se prepararán antes de solicitar la
instalación. Deberán usar fixtures sintéticos y fases separadas de preparación,
ejecución y limpieza.
