import type {
  ClosePalletCommand,
  ClosedPallet,
} from "../model/palletClose";

type ApiProblem = {
  code?: string;
};

export class PalletCloseApiError extends Error {
  constructor(
    message: string,
    readonly code: string,
    readonly status: number,
    readonly retryable: boolean,
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
  const error = toSafeError(problem.code, response.status);
  throw new PalletCloseApiError(
    error.message,
    error.code,
    response.status,
    error.retryable,
  );
}

const conflictMessages: Record<string, string> = {
  PALLET_GOOD_QUANTITY_INVALID: "La cantidad buena no es válida.",
  PALLET_CLOSER_ROLE_NOT_ALLOWED: "El empleado no puede cerrar el palé.",
  PALLET_PARTIAL_REASON_INVALID:
    "El motivo de cierre parcial no es válido.",
  ACTIVE_PALLET_RESERVATION_NOT_FOUND:
    "La reserva activa ya no está disponible.",
  PALLET_GOOD_QUANTITY_EXCEEDS_RESERVATION:
    "La cantidad supera la reserva activa.",
  PALLET_PARTIAL_CLOSE_REQUIRED: "El cierre debe marcarse como parcial.",
  PALLET_CLOSE_EXCEEDS_GOOD_TARGET:
    "El cierre supera el objetivo de producción.",
  PALLET_CLOSE_SUPERVISOR_REQUIRED:
    "Este cierre requiere un supervisor autorizador.",
  LINE_STATE_NOT_ALLOWED_FOR_PALLET_CLOSE:
    "El estado actual de la línea no admite el cierre.",
  OTHER_ACTIVE_PALLET_RESERVATIONS_EXIST:
    "Existen otras reservas activas que impiden este cierre.",
  CORRELATION_ID_REQUIRED:
    "No se ha podido identificar el intento de cierre.",
  CORRELATION_ID_ALREADY_USED:
    "El identificador de este intento ya pertenece a otra operación.",
  CORRELATION_ID_PARAMETER_MISMATCH:
    "Los datos no coinciden con el intento de cierre original.",
};

function toSafeError(
  code: string | undefined,
  status: number,
): { code: string; message: string; retryable: boolean } {
  if (status === 503) {
    return {
      code: "PALLET_CLOSE_UNAVAILABLE",
      message:
        "El servicio no puede confirmar el cierre ahora. Reintenta sin cambiar los datos.",
      retryable: true,
    };
  }

  if (code === "PREVIOUS_PALLET_OUTPUT_NOT_CONFIRMED") {
    return {
      code,
      message:
        "Palet cerrado. Esperando confirmación de NAV antes del siguiente.",
      retryable: false,
    };
  }

  if (code && conflictMessages[code]) {
    return {
      code,
      message: `${conflictMessages[code]} Revisa los datos antes de volver a confirmar.`,
      retryable: false,
    };
  }

  return {
    code: code ?? "PALLET_CLOSE_FAILED",
    message:
      status === 409
        ? "El cierre entra en conflicto con el estado actual. Revisa los datos antes de volver a confirmar."
        : "No se ha podido cerrar el palé. Revisa los datos antes de volver a confirmar.",
    retryable: false,
  };
}

async function readProblem(response: Response): Promise<ApiProblem> {
  try {
    return (await response.json()) as ApiProblem;
  } catch {
    return {};
  }
}
