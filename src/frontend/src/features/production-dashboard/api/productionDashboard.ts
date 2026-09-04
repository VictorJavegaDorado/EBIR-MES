import type { ProductionOrder } from "../../production-order-selection/model/productionOrder";
import type { ProductionTableState } from "../../production-flow/api/productionTable";

export type ProductionDashboardLine = {
  lineId: number;
  lineCode: string;
  lineName: string;
  workCenterCode: string;
  workCenterName: string;
  operationalState: string;
  blockReason: string | null;
  updatedAtUtc: string | null;
  order: ProductionOrder | null;
  table: ProductionTableState | null;
  closedPallets: number;
  latestNavState: string | null;
  latestLabelState: string | null;
  pendingNavOutputs: number;
  navIssues: number;
  pendingPrintJobs: number;
  printIssues: number;
  theoreticalUnitsToDate: number;
};

export type ProductionDashboardSnapshot = {
  serverTimeUtc: string;
  lines: ProductionDashboardLine[];
};

type ApiProblem = { detail?: string };

export async function getProductionDashboard(
  signal?: AbortSignal,
): Promise<ProductionDashboardSnapshot> {
  const response = await fetch("/api/production-dashboard", {
    headers: { Accept: "application/json" },
    signal,
  });
  if (response.ok) return (await response.json()) as ProductionDashboardSnapshot;

  let problem: ApiProblem = {};
  try {
    problem = (await response.json()) as ApiProblem;
  } catch {
    // Preserve a stable public fallback for non-JSON failures.
  }
  throw new Error(problem.detail ?? "No se puede actualizar el panel de fabricacion.");
}
