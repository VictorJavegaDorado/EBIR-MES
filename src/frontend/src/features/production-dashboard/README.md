# Production dashboard

- api/productionDashboard.ts: contrato de la instantánea (opcionalmente
  filtrada por jefe de línea) y de la lista de jefes con líneas asignadas.
- api/lineAssignments.ts: contrato de lectura de todas las líneas con su jefe
  vigente y de guardado de la selección propia de un jefe.
- ui/SupervisorIdentificationScreen.tsx: pantalla de identificación RFID,
  reutiliza `authorizeSupervisorByRfid` de `features/supervisor-access`.
- ui/LineAssignmentPicker.tsx: pantalla de selección de mesas agrupadas por
  centro de trabajo; una línea con jefe vigente distinto queda bloqueada.
- ui/ProductionDashboardPage.tsx: vista por jefe (tarjetas completas o
  compactas) y vista de planta (tarjetas mínimas), refresco cada cinco
  segundos, selector de jefe fijado en la URL (`?jefe=<codigo NAV>`) para la
  vista de solo lectura, y orquesta identificación → selección → panel propio
  para el jefe que se identifica en la propia pantalla (identidad guardada en
  `sessionStorage`, clave `mes.dashboard.supervisor`).
- ui/productionDashboard.css: composición fija para 1920×940 sin scroll y
  variantes compacta y de planta.

La lectura periódica de la feature es de solo lectura y está disponible en
/dashboard. El semáforo, el cumplimiento y el promedio de operarios usan el
mismo cálculo y los mismos umbrales que la mesa de producción. La única
escritura es la selección propia de mesas de un jefe ya identificado.
