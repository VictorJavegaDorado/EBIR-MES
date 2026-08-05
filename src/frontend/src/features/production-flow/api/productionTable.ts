export type ProductionTableOperator = {
  employeeId: number;
  navEmployeeCode: string;
  fullName: string;
  entryAtUtc: string;
  productiveSeconds: number;
  status: "PRODUCIENDO" | "EN_PAUSA";
};

export type ProductionTableState = {
  lineSessionId: number;
  orderId: number;
  lineId: number;
  state: string;
  startedAtUtc: string | null;
  serverTimeUtc: string;
  productiveSeconds: number;
  activeResources: number;
  currentTheoreticalCapacityPerHour: number;
  palletFormatCode: string;
  unitsPerPallet: number;
  operators: ProductionTableOperator[];
};

type ApiProblem = { code?: string; detail?: string };

export class ProductionTableApiError extends Error {
  constructor(readonly code: string, message = "No se puede actualizar la mesa de producción.") {
    super(message);
    this.name = "ProductionTableApiError";
  }
}

export async function startOrJoinProductionTable(
  orderId: number,
  lineId: number,
  employeeId: number,
  correlationId: string,
  signal?: AbortSignal,
): Promise<void> {
  const response = await fetch("/api/production-workstations/start-or-join", {
    method: "POST",
    headers: { Accept: "application/json", "Content-Type": "application/json" },
    body: JSON.stringify({ orderId, lineId, employeeId, correlationId }),
    signal,
  });

  if (!response.ok) throw await toError(response);
}

export async function getProductionTableState(
  orderId: number,
  lineId: number,
  signal?: AbortSignal,
): Promise<ProductionTableState | null> {
  const query = new URLSearchParams({
    orderId: String(orderId),
    lineId: String(lineId),
  });
  const response = await fetch(`/api/production-workstations/state?${query}`, {
    headers: { Accept: "application/json" },
    signal,
  });

  if (response.ok) return (await response.json()) as ProductionTableState;
  if (response.status === 404) return null;
  throw await toError(response);
}

async function toError(response: Response): Promise<ProductionTableApiError> {
  let problem: ApiProblem = {};
  try {
    problem = (await response.json()) as ApiProblem;
  } catch {
    // Keep a stable public fallback if the response has no JSON body.
  }
  return new ProductionTableApiError(
    problem.code ?? "PRODUCTION_TABLE_FAILED",
    problem.detail,
  );
}
