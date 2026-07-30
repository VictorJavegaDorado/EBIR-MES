# LineIdentification

Ubicaciones equivalentes:

- Reglas: `docs/modules/line-identification.md`.
- Frontend: `src/frontend/src/features/line-identification`.
- Pruebas:
  `tests/backend/Ebir.Mes.Application.Tests/LineIdentification` y
  `tests/backend/Ebir.Mes.IntegrationTests/LineIdentification`.

`IdentifyLine` contiene la normalización y las decisiones funcionales.
`ILineIdentificationReader` es el límite concreto con infraestructura que
permite probar esas reglas sin acceder a SQL. No es una abstracción genérica de
repositorio.

La consulta es de solo lectura y no abre una sesión ni cambia el estado de la
línea.
