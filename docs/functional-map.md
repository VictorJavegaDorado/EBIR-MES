# Mapa funcional

Este archivo es el indice de navegacion por funcionalidad. Los nombres se
mantendran estables aunque la implementacion interna evolucione.

| Funcionalidad | Reglas | Backend | Frontend | Pruebas |
|---|---|---|---|---|
| Sincronizacion de ordenes de produccion | `modules/production-order-sync.md` | `Application/ProductionOrders`, `Integrations/Navision`, `Infrastructure/ProductionOrders`, `Api/Endpoints/ProductionOrders` | `features/production-order-selection`, integrada en `features/production-flow` | `Application.Tests/ProductionOrders`, `Integrations.Tests/Navision`, `IntegrationTests/ProductionOrders`, `component/features/production-flow` |
| Seleccion de orden de produccion | `modules/production-order-sync.md` | `Application/ProductionOrders`, `Infrastructure/ProductionOrders`, `Api/Endpoints/ProductionOrders` | `features/production-order-selection` | `Application.Tests/ProductionOrders`, `IntegrationTests/ProductionOrders`, `component/features/production-order-selection` |
| Identificacion de linea | `modules/line-identification.md` | `Application/LineIdentification` | `features/line-identification` | `Application.Tests/LineIdentification`, `IntegrationTests/LineIdentification`, `component/features/line-identification` |
| Sesiones, turnos y fichajes | `modules/line-operations.md` | `Application/LineSessions`, `Infrastructure/LineSessions`, `Api/Endpoints/LineSessions` | `features/line-session` | `Application.Tests/LineSessions`, `IntegrationTests/LineSessions` |
| Mesa de produccion | `modules/production-workstation.md` | `Application/ProductionWorkstations`, `Infrastructure/ProductionWorkstations`, `Api/Endpoints/ProductionWorkstations` | `features/production-flow` | `Application.Tests/ProductionWorkstations`, `IntegrationTests/ProductionWorkstations`, `component/features/production-flow` |
| Cierre manual de pale | `modules/palletization.md` | `Application/Pallets/ClosePallet`, `Application/Pallets/ClosePalletOptions`, `Api/Endpoints/Pallets` | `features/pallet-close`, integrado dentro de `features/production-flow` | `Application.Tests/Pallets`, `IntegrationTests/Pallets`, `component/features/pallet-close`, `component/features/production-flow` |
| Salida de palet hacia NAV | `modules/nav-pallet-output.md` | `Application/NavisionOutput`, `Infrastructure/NavisionOutput`, `Integrations/NavisionOutput`, `Worker/NavisionPalletOutputWorker`; NAV: 50013, 50036, 50056, 60103 y 82000 mediante `deploy/nav/NAV-001A`; administracion Job Queue mediante `deploy/nav/NAV-001B` y recurrencia controlada mediante `deploy/nav/NAV-001C` | Estado dentro de `features/production-flow` | `Application.Tests/NavisionOutput`, `Integrations.Tests/NavisionOutput`, `database/nav_pallet_output_queue`, `nav/autonomous_mes_output`, `nav/job_queue_mes_admin`, `nav/job_queue_mes_recurring` |
| Scrap | `modules/scrap-replenishment.md` | `Application/Scrap` | `features/scrap-register` | `Application.Tests/Scrap` |
| Reaprovisionamiento | `modules/scrap-replenishment.md` | `Application/Replenishment` | `features/replenishment-request` | `Application.Tests/Replenishment` |
| Impresion | `modules/palletization.md` | `Integrations/Printing`, `Integrations.Windows/Printing`, `Worker/PrintingWorker` | Estado dentro de la feature | `Application.Tests/Printing`, `Integrations.Tests/Printing`, `Integrations.Windows.Tests/Printing`, `IntegrationTests/Printing` |
| Reimpresion supervisada de etiqueta de palet | `modules/palletization.md` | `Application/Printing/ReprintPalletLabel`, `Infrastructure/Printing`, `Api/Endpoints/Printing`; SQL: `database/038A_reimpresion_etiqueta_palet.sql` | `features/label-reprint`, integrado en el resultado de cierre | `Application.Tests/Printing`, `IntegrationTests/Printing`, `component/features/label-reprint`, `database/label_reprint` |
| Maestros del piloto TEST | `modules/pilot-master-data.md` | Configuracion externa; sin caso de uso runtime | No aplica | `database/pilot_master_data` |

Una fila se anade cuando comienza la implementacion de la funcionalidad, no
para anticipar modulos hipoteticos.
