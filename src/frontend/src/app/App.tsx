import { ProductionFlowPage } from "../features/production-flow/ui/ProductionFlowPage";
import "../features/production-flow/ui/productionFlow.css";
import { ProductionDashboardPage } from "../features/production-dashboard/ui/ProductionDashboardPage";
import "../features/production-dashboard/ui/productionDashboard.css";
import { AppShell } from "../widgets/app-shell/ui/AppShell";

export function App() {
  const dashboard = window.location.pathname.replace(/\/+$/, "").toLowerCase() === "/dashboard";
  return (
    <AppShell variant={dashboard ? "dashboard" : "production"}>
      {dashboard ? <ProductionDashboardPage /> : <ProductionFlowPage />}
    </AppShell>
  );
}
