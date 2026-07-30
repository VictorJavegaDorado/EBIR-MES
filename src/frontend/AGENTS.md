# Instrucciones del frontend

- Sigue la organización `app`, `features`, `entities`, `widgets` y `shared`.
- Una interacción de negocio vive en `features/<nombre-funcional>`.
- Un concepto reutilizable del dominio puede vivir en `entities`; no muevas
  componentes allí antes de que exista reutilización real.
- `shared` solo contiene piezas sin conocimiento del negocio.
- No reproduzcas reglas de negocio del backend. Presenta las acciones y errores
  que la API devuelva.
- Prioriza uso táctil: objetivos grandes, contraste, estados inequívocos y
  recuperación clara ante errores.
- No añadas un estado global, un design system o una abstracción de peticiones
  hasta que una funcionalidad real los necesite.
- Las pruebas deben reflejar la ruta de la feature en `tests/frontend`.

