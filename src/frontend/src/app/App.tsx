import { ProductionFlowPage } from "../features/production-flow/ui/ProductionFlowPage";
import "../features/production-flow/ui/productionFlow.css";
import { AppShell } from "../widgets/app-shell/ui/AppShell";

export function App() {
  return (
    <AppShell>
      <ProductionFlowPage />
    </AppShell>
  );
}
