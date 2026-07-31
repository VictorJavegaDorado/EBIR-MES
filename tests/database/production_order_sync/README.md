# Pruebas del paquete 015

Estado: **instalado y validado el 31/07/2026**.

`verify-015-static.ps1` comprueba guardas, objetos, bloqueos de idempotencia,
rechazo de correlaciones incompatibles y permiso de runtime. Solo lee el archivo
SQL: no abre conexiones ni ejecuta instrucciones contra una base de datos.

La validacion autorizada posterior cubrio instalacion, permiso runtime, lectura
real de NAV, los tres resultados idempotentes, restauracion del snapshot,
limpieza y `DBCC CHECKDB`. El detalle se conserva en
`RESULTADO_EJECUCION_2026-07-31.md`.
