# Instrucciones de pruebas

- Refleja la ruta funcional del código probado.
- Las pruebas unitarias no acceden a SQL Server ni a sistemas externos.
- Las pruebas de integración solo pueden usar `EBIR_MES_TEST`.
- Ninguna prueba llama a NAV, RFID físico o impresoras reales.
- Los fixtures deben ser sintéticos, reconocibles y eliminables.
- Separa expresamente preparación, ejecución y limpieza cuando una prueba SQL
  requiera autorizaciones distintas.

