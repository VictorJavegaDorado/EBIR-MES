# Revision del paquete 015

`verify-015-static.ps1` comprueba guardas, objetos, bloqueos de idempotencia,
rechazo de correlaciones incompatibles y permiso de runtime. Solo lee el archivo
SQL: no abre conexiones ni ejecuta instrucciones contra una base de datos.
