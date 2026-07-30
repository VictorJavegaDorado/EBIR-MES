import type {
  ClosePalletCommand,
  ClosedPallet,
} from "../model/palletClose";

type ApiProblem = {
  title?: string;
  detail?: string;
  code?: string;
};

export class PalletCloseApiError extends Error {
  constructor(
    message: string,
    readonly code: string,
    readonly status: number,
  ) {
    super(message);
    this.name = "PalletCloseApiError";
  }
}

export async function closePallet(
  reservationId: number,
  command: ClosePalletCommand,
  signal?: AbortSignal,
): Promise<ClosedPallet> {
  const response = await fetch(
    `/api/pallet-reservations/${reservationId}/close`,
    {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
      body: JSON.stringify(command),
      signal,
    },
  );

  if (response.ok) {
    return (await response.json()) as ClosedPallet;
  }

  const problem = await readProblem(response);
  throw new PalletCloseApiError(
    problem.detail ?? problem.title ?? "No se ha podido cerrar el palé.",
    problem.code ?? "PALLET_CLOSE_FAILED",
    response.status,
  );
}

async function readProblem(response: Response): Promise<ApiProblem> {
  try {
    return (await response.json()) as ApiProblem;
  } catch {
    return {};
  }
}
