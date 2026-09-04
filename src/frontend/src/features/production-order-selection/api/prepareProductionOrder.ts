import type { ProductionOrder } from "../model/productionOrder";

type ApiProblem = { code?: string; detail?: string };

export class ProductionOrderPreparationApiError extends Error {
  constructor(readonly code: string, message?: string) {
    super(message ?? "No se puede preparar la orden para producción.");
    this.name = "ProductionOrderPreparationApiError";
  }
}

export async function prepareProductionOrder(
  orderNumber: string,
  correlationId: string,
  signal?: AbortSignal,
): Promise<ProductionOrder> {
  const response = await fetch("/api/production-orders/prepare", {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ orderNumber, correlationId }),
    signal,
  });
  if (response.ok) {
    return (await response.json()) as ProductionOrder;
  }

  let problem: ApiProblem = {};
  try {
    problem = (await response.json()) as ApiProblem;
  } catch {
    // Keep a stable operator-facing fallback when the server has no JSON body.
  }
  throw new ProductionOrderPreparationApiError(
    problem.code ?? "PRODUCTION_ORDER_PREPARATION_FAILED",
    problem.detail,
  );
}
