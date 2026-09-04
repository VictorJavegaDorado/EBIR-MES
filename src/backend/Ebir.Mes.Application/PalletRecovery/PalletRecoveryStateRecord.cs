namespace Ebir.Mes.Application.PalletRecovery;

public sealed record PalletRecoveryStateRecord(
    long PalletId,
    int PalletNumber,
    long? NavOperationId,
    string? NavState,
    int NavAttempts,
    bool NavReconciliationRetryAvailable,
    string? LabelState,
    bool LabelReprintAvailable);
