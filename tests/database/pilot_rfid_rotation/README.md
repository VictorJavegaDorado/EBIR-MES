# Pruebas del paquete 020

- `verify-020-static.ps1` comprueba destino, transaccion, revocacion, alta,
  auditoria, parametrizacion y ausencia de valores protegidos. No abre SQL.
- `00_PREVUELO_020.sql` valida en lectura los dos empleados, sus roles y sus
  credenciales activas sin mostrar nombres ni huellas.
- `install-020.ps1 -ValidateOnly` ejecuta toda la rotacion dentro de una
  transaccion exterior y termina con `ROLLBACK`.

La configuracion real permanece protegida fuera del repositorio. Ninguna prueba
debe imprimir o persistir los valores originales de las tarjetas.
