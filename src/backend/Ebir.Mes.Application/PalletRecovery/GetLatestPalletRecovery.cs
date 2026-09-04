namespace Ebir.Mes.Application.PalletRecovery;

public sealed class GetLatestPalletRecovery(IPalletRecoveryStateReader reader)
{
    public Task<PalletRecoveryStateRecord?> ExecuteAsync(
        long lineSessionId,
        CancellationToken cancellationToken) =>
        reader.ReadLatestAsync(lineSessionId, cancellationToken);
}
