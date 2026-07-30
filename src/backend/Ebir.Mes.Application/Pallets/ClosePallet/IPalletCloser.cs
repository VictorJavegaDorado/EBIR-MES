namespace Ebir.Mes.Application.Pallets.ClosePallet;

public interface IPalletCloser
{
    Task<ClosedPalletRecord> CloseAsync(
        ClosePalletCommand command,
        CancellationToken cancellationToken);
}
