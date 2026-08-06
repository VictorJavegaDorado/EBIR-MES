namespace Ebir.Mes.Application.NavisionOutput;

public interface INavisionPalletOutputSender
{
    Task<NavisionPalletOutputReceipt> SendAsync(
        NavisionPalletOutputJob job,
        CancellationToken cancellationToken);
}
