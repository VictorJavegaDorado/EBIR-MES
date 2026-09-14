# Production dashboard

- api/productionDashboard.ts: contrato de la instantánea (opcionalmente
  filtrada por jefe de línea) y de la lista de jefes con líneas asignadas.
- ui/ProductionDashboardPage.tsx: vista por jefe (tarjetas completas o
  compactas) y vista de planta (tarjetas mínimas), refresco cada cinco
  segundos, selector de jefe fijado en la URL (`?jefe=<codigo NAV>`).
- ui/productionDashboard.css: composición fija para 1920×940 sin scroll y
  variantes compacta y de planta.

La feature es de solo lectura y está disponible en /dashboard. El semáforo,
el cumplimiento y el promedio de operarios usan el mismo cálculo y los mismos
umbrales que la mesa de producción.
