import type {
  LabelReprintCommand,
  QueuedLabelReprint,
} from "../model/labelReprint";

type ApiProblem = { code?: string };

export class LabelReprintApiError extends Error {
  constructor(
    message: string,
    readonly code: string,
    readonly retryable: boolean,
  ) {
    super(message);
    this.name = "LabelReprintApiError";
  }
}

export async function reprintPalletLabel(
  palletId: number,
  command: LabelReprintCommand,
  signal?: AbortSignal,
): Promise<QueuedLabelReprint> {
  const response = await fetch(`/api/pallets/${palletId}/label-reprints`, {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(command),
    signal,
  });

  if (response.ok) return (await response.json()) as QueuedLabelReprint;

  const problem = await readProblem(response);
  const error = toSafeError(problem.code, response.status);
  throw new LabelReprintApiError(error.message, error.code, error.retryable);
}

const conflictMessages: Record<string, string> = {
  REPRINT_SUPERVISOR_NOT_ACTIVE:
    "El supervisor ya no está disponible para autorizar la copia.",
  PALLET_NOT_FOUND: "El palé ya no está disponible.",
  PALLET_LABEL_NOT_FOUND: "El palé no tiene una etiqueta disponible.",
  PALLET_LABEL_NOT_PRINTED:
    "La etiqueta original todavía no consta como impresa.",
  ORIGINAL_PRINT_NOT_COMPLETED:
    "La impresión original todavía no ha terminado.",
  PALLET_LABEL_PRINT_ALREADY_OPEN:
    "Ya existe una impresión pendiente para esta etiqueta.",
  PRIMARY_PRINTER_NOT_AVAILABLE:
    "La línea no tiene una impresora principal disponible.",
  CORRELATION_ID_ALREADY_USED:
    "El identificador del intento ya pertenece a otra operación.",
  CORRELATION_ID_PARAMETER_MISMATCH:
    "Los datos no coinciden con el intento de reimpresión original.",
};

function toSafeError(
  code: string | undefined,
  status: number,
): { code: string; message: string; retryable: boolean } {
  if (status === 503) {
    return {
      code: "PALLET_LABEL_REPRINT_UNAVAILABLE",
      message: "No se puede solicitar la copia ahora. Reintenta sin cambiar los datos.",
      retryable: true,
    };
  }

  const resolved = code ?? "PALLET_LABEL_REPRINT_FAILED";
  const retryable = [
    "PALLET_LABEL_NOT_PRINTED",
    "ORIGINAL_PRINT_NOT_COMPLETED",
    "PALLET_LABEL_PRINT_ALREADY_OPEN",
    "PRIMARY_PRINTER_NOT_AVAILABLE",
  ].includes(resolved);
  return {
    code: resolved,
    message: conflictMessages[resolved]
      ?? "No se ha podido solicitar la copia. Revisa los datos.",
    retryable,
  };
}

async function readProblem(response: Response): Promise<ApiProblem> {
  try {
    return (await response.json()) as ApiProblem;
  } catch {
    return {};
  }
}
