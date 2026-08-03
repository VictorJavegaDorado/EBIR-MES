export type IdentifiedEmployee = {
  employeeId: number;
  navEmployeeCode: string;
  fullName: string;
};

type ApiProblem = {
  code?: string;
};

export class RfidIdentificationApiError extends Error {
  constructor(readonly code: string) {
    super("No se ha podido identificar la tarjeta.");
    this.name = "RfidIdentificationApiError";
  }
}

export async function identifyEmployeeByRfid(
  credential: string,
  signal?: AbortSignal,
): Promise<IdentifiedEmployee> {
  const response = await fetch("/api/operator-identification/rfid", {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ credential }),
    signal,
  });

  if (response.ok) {
    return (await response.json()) as IdentifiedEmployee;
  }

  let problem: ApiProblem = {};
  try {
    problem = (await response.json()) as ApiProblem;
  } catch {
    // Keep the public fallback stable when there is no JSON body.
  }

  throw new RfidIdentificationApiError(
    problem.code ?? "RFID_IDENTIFICATION_FAILED",
  );
}
