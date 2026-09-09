export type AuthorizedSupervisor = {
  employeeId: number;
  navEmployeeCode: string;
  fullName: string;
};

type ApiProblem = { code?: string };

export class SupervisorAccessApiError extends Error {
  constructor(readonly code: string) {
    super("No se ha podido autorizar el acceso.");
    this.name = "SupervisorAccessApiError";
  }
}

export async function authorizeSupervisorByRfid(
  credential: string,
  signal?: AbortSignal,
): Promise<AuthorizedSupervisor> {
  const response = await fetch("/api/supervisor-access/rfid", {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ credential }),
    signal,
  });
  if (response.ok) return (await response.json()) as AuthorizedSupervisor;

  let problem: ApiProblem = {};
  try {
    problem = (await response.json()) as ApiProblem;
  } catch {
    // Preserve a stable public fallback if the response has no JSON body.
  }
  throw new SupervisorAccessApiError(
    problem.code ?? "RFID_SUPERVISOR_AUTHORIZATION_UNAVAILABLE",
  );
}
