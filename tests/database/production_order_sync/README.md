# Pruebas del paquete 015

Estado: **instalado y validado el 31/07/2026**.

`verify-015-static.ps1` comprueba guardas, objetos, bloqueos de idempotencia,
rechazo de correlaciones incompatibles y permiso de runtime. Solo lee el archivo
SQL: no abre conexiones ni ejecuta instrucciones contra una base de datos.

La validacion autorizada posterior cubrio instalacion, permiso runtime, lectura
real de NAV, los tres resultados idempotentes, restauracion del snapshot,
limpieza y `DBCC CHECKDB`. El detalle se conserva en
`RESULTADO_EJECUCION_2026-07-31.md`.

`run-controlled-api-sync.ps1` ejecuta de forma explicita el disparador HTTP con
una API publicada temporalmente. Solo admite `EBIR_MES_TEST`, exige
`NT AUTHORITY\NETWORK SERVICE` y el modificador
`-ConfirmAuthorizedExecution`, escucha exclusivamente en bucle local y repite
la misma correlacion para verificar la idempotencia. No instala SQL, no activa
IIS y no escribe en NAV.

La primera ejecucion mediante el endpoint se documenta en
`RESULTADO_ENDPOINT_2026-07-31.md`. El snapshot real queda conservado en la
bandeja para preparar su promocion posterior.
