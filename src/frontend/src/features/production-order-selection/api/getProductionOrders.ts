import type { ProductionOrder } from "../model/productionOrder";

type ApiProblem = { code?: string };

export class ProductionOrderSelectionApiError extends Error {
  constructor(readonly code: string) {
    super("No se pueden cargar las órdenes. Vuelve a intentarlo.");
    this.name = "ProductionOrderSelectionApiError";
  }
}

export async function getProductionOrders(
  signal?: AbortSignal,
): Promise<ProductionOrder[]> {
  const response = await fetch("/api/production-orders", {
    headers: { Accept: "application/json" },
    signal,
  });
  if (response.ok) {
    return (await response.json()) as ProductionOrder[];
  }

  let problem: ApiProblem = {};
  try {
    problem = (await response.json()) as ApiProblem;
  } catch {
    // The public fallback remains stable when the server has no JSON body.
  }
  throw new ProductionOrderSelectionApiError(
    problem.code ?? "PRODUCTION_ORDER_SELECTION_FAILED",
  );
}
