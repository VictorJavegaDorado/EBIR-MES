import type { IdentifiedLine } from "../model/lineIdentification";

type ApiProblem = {
  title?: string;
  detail?: string;
  code?: string;
};

export class LineIdentificationApiError extends Error {
  constructor(
    message: string,
    readonly code: string,
    readonly status: number,
  ) {
    super(message);
    this.name = "LineIdentificationApiError";
  }
}

export async function identifyLine(
  code: string,
  signal?: AbortSignal,
): Promise<IdentifiedLine> {
  const response = await fetch(`/api/lines/${encodeURIComponent(code)}`, {
    headers: { Accept: "application/json" },
    signal,
  });

  if (response.ok) {
    return (await response.json()) as IdentifiedLine;
  }

  const problem = await readProblem(response);
  throw new LineIdentificationApiError(
    problem.detail ?? problem.title ?? "No se ha podido identificar la línea.",
    problem.code ?? "LINE_IDENTIFICATION_FAILED",
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
