# Mapa funcional

Este archivo es el índice de navegación por funcionalidad. Los nombres se
mantendrán estables aunque la implementación interna evolucione.

| Funcionalidad | Reglas | Backend | Frontend | Pruebas |
|---|---|---|---|---|
| Sincronización de órdenes de producción | `modules/production-order-sync.md` | `Application/ProductionOrders`, `Integrations/Navision` | Pendiente | `Integrations.Tests/Navision` |
| Identificación de línea | `modules/line-identification.md` | `Application/LineIdentification` | `features/line-identification` | `Application.Tests/LineIdentification`, `IntegrationTests/LineIdentification`, `component/features/line-identification` |
| Sesiones, turnos y fichajes | `modules/line-operations.md` | `Application/LineSessions`, `Infrastructure/LineSessions`, `Api/Endpoints/LineSessions` | `features/line-session` | `Application.Tests/LineSessions`, `IntegrationTests/LineSessions` |
| Cierre manual de palé | `modules/palletization.md` | `Application/Pallets/ClosePallet`, `Application/Pallets/ClosePalletOptions`, `Api/Endpoints/Pallets` | `features/pallet-close`, integración en `app/App.tsx` | `Application.Tests/Pallets`, `IntegrationTests/Pallets`, `component/features/pallet-close` |
| Scrap | `modules/scrap-replenishment.md` | `Application/Scrap` | `features/scrap-register` | `Application.Tests/Scrap` |
| Reaprovisionamiento | `modules/scrap-replenishment.md` | `Application/Replenishment` | `features/replenishment-request` | `Application.Tests/Replenishment` |
| Impresión | Documento del módulo consumidor | `Integrations/Printing` | Estado dentro de la feature | `IntegrationTests/Printing` |

Una fila se añade cuando comienza la implementación de la funcionalidad, no
para anticipar módulos hipotéticos.
