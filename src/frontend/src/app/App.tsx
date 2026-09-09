import { ProductionFlowPage } from "../features/production-flow/ui/ProductionFlowPage";
import "../features/production-flow/ui/productionFlow.css";
import { ProductionDashboardPage } from "../features/production-dashboard/ui/ProductionDashboardPage";
import "../features/production-dashboard/ui/productionDashboard.css";
import { LabelControlPage } from "../features/label-control/ui/LabelControlPage";
import "../features/label-control/ui/labelControl.css";
import { AppShell } from "../widgets/app-shell/ui/AppShell";

export function App() {
  const path = window.location.pathname.replace(/\/+$/, "").toLowerCase();
  const dashboard = path === "/dashboard";
  const labels = path === "/etiquetas";
  const variant = dashboard ? "dashboard" : labels ? "labels" : "production";
  return (
    <AppShell variant={variant}>
      {dashboard
        ? <ProductionDashboardPage />
        : labels ? <LabelControlPage /> : <ProductionFlowPage />}
    </AppShell>
  );
}
