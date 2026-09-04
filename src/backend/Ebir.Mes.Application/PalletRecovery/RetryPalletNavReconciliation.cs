namespace Ebir.Mes.Application.PalletRecovery;

public sealed class RetryPalletNavReconciliation(
    IPalletNavReconciliationRetrier retrier)
{
    public const int MaximumReasonLength = 500;

    public async Task<RetriedPalletNavReconciliationRecord> ExecuteAsync(
        RetryPalletNavReconciliationCommand command,
        CancellationToken cancellationToken)
    {
        var reason = command.Reason?.Trim() ?? string.Empty;
        if (command.NavOperationId <= 0)
            throw new PalletRecoveryRejectedException(
                "NAV_OPERATION_ID_INVALID", "La operacion NAV no es valida.");
        if (command.RequestedBySupervisorId <= 0)
            throw new PalletRecoveryRejectedException(
                "NAV_RETRY_SUPERVISOR_REQUIRED", "La conciliacion requiere un supervisor.");
        if (reason.Length is 0 or > MaximumReasonLength)
            throw new PalletRecoveryRejectedException(
                "NAV_RETRY_REASON_INVALID", "El motivo de conciliacion no es valido.");
        if (command.CorrelationId == Guid.Empty)
            throw new PalletRecoveryRejectedException(
                "CORRELATION_ID_REQUIRED", "La correlacion es obligatoria.");

        return await retrier.RetryAsync(
            command with { Reason = reason }, cancellationToken);
    }
}
