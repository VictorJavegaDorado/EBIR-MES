namespace Ebir.Mes.Application.PalletRecovery;

public interface IPalletNavReconciliationRetrier
{
    Task<RetriedPalletNavReconciliationRecord> RetryAsync(
        RetryPalletNavReconciliationCommand command,
        CancellationToken cancellationToken);
}
