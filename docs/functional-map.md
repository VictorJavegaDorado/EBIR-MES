# Mapa funcional

Este archivo es el índice de navegación por funcionalidad. Los nombres se
mantendrán estables aunque la implementación interna evolucione.

| Funcionalidad | Reglas | Backend | Frontend | Pruebas |
|---|---|---|---|---|
| Identificación de línea | `modules/line-identification.md` | `Application/LineIdentification` | `features/line-identification` | `Application.Tests/LineIdentification`, `IntegrationTests/LineIdentification`, `component/features/line-identification` |
| Sesiones, turnos y fichajes | `modules/line-operations.md` | `Application/LineSessions` | `features/line-session` | `Application.Tests/LineSessions` |
| Cierre manual de palé | `modules/palletization.md` | `Application/Pallets/ClosePallet` | `features/pallet-close` | `Application.Tests/Pallets/ClosePallet` |
| Scrap | `modules/scrap-replenishment.md` | `Application/Scrap` | `features/scrap-register` | `Application.Tests/Scrap` |
| Reaprovisionamiento | `modules/scrap-replenishment.md` | `Application/Replenishment` | `features/replenishment-request` | `Application.Tests/Replenishment` |
| Impresión | Documento del módulo consumidor | `Integrations/Printing` | Estado dentro de la feature | `IntegrationTests/Printing` |

Una fila se añade cuando comienza la implementación de la funcionalidad, no
para anticipar módulos hipotéticos.
