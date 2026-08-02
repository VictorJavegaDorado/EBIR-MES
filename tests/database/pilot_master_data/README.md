# Pruebas del paquete 019

- `verify-019-static.ps1` comprueba guardas, transacción, parametrización y
  ausencia de valores físicos o secretos. No abre SQL.
- `00_PREVUELO_019.sql` valida en modo lectura los objetos, el centro, los roles
  y muestra únicamente recuentos de maestros.
- `install-019.ps1 -ValidateOnly` carga una configuración externa mediante
  parámetros, ejecuta el paquete completo y revierte la transacción exterior.

No se incluye un fixture JSON porque contendría nombres, configuración física y
huellas RFID. Para una prueba automatizada deben generarse valores sintéticos
en una carpeta temporal fuera del repositorio y eliminarse al terminar.

La ejecución controlada más reciente se documenta en
`RESULTADO_VALIDACION_2026-08-02.md`.
