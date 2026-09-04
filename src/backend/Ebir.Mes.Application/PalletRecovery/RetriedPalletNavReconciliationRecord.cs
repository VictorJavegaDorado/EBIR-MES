namespace Ebir.Mes.Application.PalletRecovery;

public sealed record RetriedPalletNavReconciliationRecord(
    long NavOperationId,
    int NextAttempt);
