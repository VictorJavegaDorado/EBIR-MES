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
  resourceSeconds: number;
  supervisorNavEmployeeCode: string | null;
  supervisorName: string | null;
};

export type ProductionDashboardSupervisorLine = {
  lineId: number;
  lineCode: string;
  lineName: string;
};

export type ProductionDashboardSupervisor = {
  navEmployeeCode: string;
  fullName: string;
  lines: ProductionDashboardSupervisorLine[];
};

export type ProductionDashboardSnapshot = {
  serverTimeUtc: string;
  lines: ProductionDashboardLine[];
  supervisor?: ProductionDashboardSupervisor | null;
};

type ApiProblem = { detail?: string };

export async function getProductionDashboard(
  supervisorNavEmployeeCode: string | null,
  signal?: AbortSignal,
): Promise<ProductionDashboardSnapshot> {
  const query = supervisorNavEmployeeCode
    ? `?${new URLSearchParams({ supervisor: supervisorNavEmployeeCode })}`
    : "";
  const response = await fetch(`/api/production-dashboard${query}`, {
    headers: { Accept: "application/json" },
    signal,
  });
  if (response.ok) return (await response.json()) as ProductionDashboardSnapshot;
  throw new Error(await readDetail(response) ?? "No se puede actualizar el panel de fabricacion.");
}

export async function getProductionDashboardSupervisors(
  signal?: AbortSignal,
): Promise<ProductionDashboardSupervisor[]> {
  const response = await fetch("/api/production-dashboard/supervisors", {
    headers: { Accept: "application/json" },
    signal,
  });
  if (response.ok) return (await response.json()) as ProductionDashboardSupervisor[];
  throw new Error(await readDetail(response) ?? "No se pueden cargar los jefes de línea.");
}

async function readDetail(response: Response): Promise<string | undefined> {
  try {
    return ((await response.json()) as ApiProblem).detail;
  } catch {
    // Preserve a stable public fallback for non-JSON failures.
    return undefined;
  }
}
