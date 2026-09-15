export type LineAssignmentOption = {
  lineId: number;
  lineCode: string;
  lineName: string;
  workCenterCode: string;
  workCenterName: string;
  supervisorNavEmployeeCode: string | null;
  supervisorName: string | null;
};

type ApiProblem = { code?: string };

export class LineAssignmentApiError extends Error {
  constructor(readonly code: string) {
    super("No se ha podido gestionar la selección de mesas.");
    this.name = "LineAssignmentApiError";
  }
}

async function parseError(response: Response): Promise<never> {
  let problem: ApiProblem = {};
  try {
    problem = (await response.json()) as ApiProblem;
  } catch {
    // Keep the public fallback stable when there is no JSON body.
  }
  throw new LineAssignmentApiError(problem.code ?? "LINE_ASSIGNMENT_UNAVAILABLE");
}

export async function getLineAssignmentOptions(
  signal?: AbortSignal,
): Promise<LineAssignmentOption[]> {
  const response = await fetch("/api/production-dashboard/line-assignments", {
    headers: { Accept: "application/json" },
    signal,
  });
  if (!response.ok) return parseError(response);
  return (await response.json()) as LineAssignmentOption[];
}

export async function setLineAssignments(
  employeeId: number,
  lineIds: number[],
  signal?: AbortSignal,
): Promise<LineAssignmentOption[]> {
  const response = await fetch("/api/production-dashboard/line-assignments", {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ employeeId, lineIds }),
    signal,
  });
  if (!response.ok) return parseError(response);
  return (await response.json()) as LineAssignmentOption[];
}
