import type { PalletCloseOptions } from "../model/palletClose";

type ApiProblem = {
  code?: string;
};

export class PalletCloseOptionsApiError extends Error {
  constructor(readonly code: string) {
    super(
      "No se pueden cargar las reservas y empleados. Vuelve a intentarlo.",
    );
    this.name = "PalletCloseOptionsApiError";
  }
}

export async function getPalletCloseOptions(
  lineId: number,
  signal?: AbortSignal,
): Promise<PalletCloseOptions> {
  const response = await fetch(
    `/api/lines/${lineId}/pallet-close-options`,
    {
      headers: { Accept: "application/json" },
      signal,
    },
  );

  if (response.ok) {
    return (await response.json()) as PalletCloseOptions;
  }

  const problem = await readProblem(response);
  throw new PalletCloseOptionsApiError(
    problem.code ?? "PALLET_CLOSE_OPTIONS_FAILED",
  );
}

async function readProblem(response: Response): Promise<ApiProblem> {
  try {
    return (await response.json()) as ApiProblem;
  } catch {
    return {};
  }
}
