export type PalletRecoveryState = {
  palletId: number;
  palletNumber: number;
  navOperationId: number | null;
  navState: string | null;
  navAttempts: number;
  navReconciliationRetryAvailable: boolean;
  labelState: string | null;
  labelReprintAvailable: boolean;
};

type ApiProblem = { code?: string; detail?: string };

export class PalletRecoveryApiError extends Error {
  constructor(readonly code: string, message: string) {
    super(message);
    this.name = "PalletRecoveryApiError";
  }
}

export async function getLatestPalletRecovery(
  lineSessionId: number,
  signal?: AbortSignal,
): Promise<PalletRecoveryState | null> {
  const response = await fetch(
    `/api/line-sessions/${lineSessionId}/latest-pallet-recovery`,
    { headers: { Accept: "application/json" }, signal },
  );
  if (response.ok) {
    if (response.status === 204) return null;
    return (await response.json()) as PalletRecoveryState;
  }
  throw await toError(response, "PALLET_RECOVERY_UNAVAILABLE");
}

export async function retryPalletNavReconciliation(
  navOperationId: number,
  requestedBySupervisorId: number,
  reason: string,
  correlationId: string,
  signal?: AbortSignal,
): Promise<void> {
  const response = await fetch(
    `/api/nav/pallet-outputs/${navOperationId}/retry-reconciliation`,
    {
      method: "POST",
      headers: { Accept: "application/json", "Content-Type": "application/json" },
      body: JSON.stringify({ requestedBySupervisorId, reason, correlationId }),
      signal,
    },
  );
  if (!response.ok) throw await toError(response, "NAV_RECONCILIATION_RETRY_FAILED");
}

async function toError(response: Response, fallback: string) {
  let problem: ApiProblem = {};
  try { problem = (await response.json()) as ApiProblem; } catch { /* stable fallback */ }
  return new PalletRecoveryApiError(
    problem.code ?? fallback,
    problem.detail ?? "No se puede completar la acción en este momento.",
  );
}
