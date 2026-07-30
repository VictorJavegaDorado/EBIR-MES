# Plan: primera vertical

Estado: implementación y pruebas sin SQL completadas el 29/07/2026. La
validación contra `EBIR_MES_TEST` queda pendiente de autorización específica y
configuración protegida de la conexión.

La primera vertical conectará una pantalla de identificación de línea con una
consulta real a la API y a `EBIR_MES_TEST`.

1. [x] Definir el contrato de consulta a partir del esquema versionado.
2. [x] Implementar el caso de uso en `Application/LineIdentification`.
3. [x] Implementar el lector parametrizado en
   `Infrastructure/LineIdentification`.
4. [x] Exponer `GET /api/lines/{code}`.
5. [x] Conectar `features/line-identification`.
6. [x] Añadir pruebas de aplicación, contrato HTTP y componente.
7. [ ] Configurar la conexión y validar la lectura contra `EBIR_MES_TEST`
   cuando exista autorización para ejecutar SQL.

No se habilitarán todavía llamadas reales a NAV, RFID ni impresión.
