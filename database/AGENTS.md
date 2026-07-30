# Instrucciones de base de datos

- Única base autorizada: `EBIR_MES_TEST` en
  `SQL.EBIR.LOCAL\NAVISION2017`.
- No ejecutes ningún script sin autorización explícita para esa fase.
- No edites un paquete ya aplicado; crea el siguiente número de paquete.
- Cada paquete debe incluir precondiciones, transacción, manejo de errores y
  validación posterior acorde a su riesgo.
- Las pruebas SQL viven en `tests/database` y deben usar fixtures sintéticos.
- Nunca añadas `USE` o referencias de tres partes a otra base.

