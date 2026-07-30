# line-identification

Vertical visual de `LineIdentification`.

- `api/identifyLine.ts`: contrato HTTP y traducción de errores de transporte.
- `model/lineIdentification.ts`: datos y estados visibles de la vertical.
- `ui/LineIdentificationPage.tsx`: entrada táctil, carga, resultado y error.
- Reglas: `docs/modules/line-identification.md`.
- Pruebas:
  `tests/frontend/component/features/line-identification`.

No contiene líneas recientes ficticias ni simula una identificación correcta.
La apertura de sesión se muestra como siguiente paso, pero permanece
deshabilitada.
