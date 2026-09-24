export type MaterialRequestOption = {
  orderComponentId: number;
  componentCode: string;
  description: string;
  unitOfMeasure: string | null;
  theoreticalQuantity: number | null;
  openRequestCount: number;
};

type ApiProblem = { code?: string; detail?: string };

export class MaterialRequestApiError extends Error {
  constructor(readonly code: string, message = "No se puede solicitar el material.") {
    super(message);
    this.name = "MaterialRequestApiError";
  }
}

export async function getMaterialRequestOptions(sessionId: number, signal?: AbortSignal) {
  const response = await fetch(`/api/line-sessions/${sessionId}/material-request-options`, {
    headers: { Accept: "application/json" }, signal,
  });
  if (!response.ok) throw await toError(response);
  return (await response.json()) as MaterialRequestOption[];
}

export async function requestMaterial(sessionId: number, orderComponentId: number,
  quantity: number, employeeId: number, correlationId: string, signal?: AbortSignal) {
  const response = await fetch(`/api/line-sessions/${sessionId}/material-requests`, {
    method: "POST",
    headers: { Accept: "application/json", "Content-Type": "application/json" },
    body: JSON.stringify({ orderComponentId, quantity, employeeId, correlationId }),
    signal,
  });
  if (!response.ok) throw await toError(response);
  return (await response.json()) as { id: number; navRequestId: number; state: string };
}

async function toError(response: Response) {
  let problem: ApiProblem = {};
  try { problem = (await response.json()) as ApiProblem; } catch { /* safe fallback */ }
  return new MaterialRequestApiError(problem.code ?? "MATERIAL_REQUEST_FAILED", problem.detail);
}
