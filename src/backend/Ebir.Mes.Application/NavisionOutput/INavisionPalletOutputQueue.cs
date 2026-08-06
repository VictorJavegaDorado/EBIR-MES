namespace Ebir.Mes.Application.NavisionOutput;

public interface INavisionPalletOutputQueue
{
    Task<NavisionPalletOutputJob?> ReserveNextAsync(
        string workerId,
        CancellationToken cancellationToken);

    Task CompleteAsync(
        NavisionPalletOutputJob job,
        NavisionPalletOutputReceipt receipt,
        Guid correlationId,
        CancellationToken cancellationToken);

    Task FailAsync(
        NavisionPalletOutputJob job,
        NavisionPalletOutputReceipt receipt,
        CancellationToken cancellationToken);
}
