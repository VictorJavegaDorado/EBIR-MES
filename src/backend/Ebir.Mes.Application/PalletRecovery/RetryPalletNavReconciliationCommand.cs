namespace Ebir.Mes.Application.PalletRecovery;

public sealed record RetryPalletNavReconciliationCommand(
    long NavOperationId,
    long RequestedBySupervisorId,
    string Reason,
    Guid CorrelationId);
