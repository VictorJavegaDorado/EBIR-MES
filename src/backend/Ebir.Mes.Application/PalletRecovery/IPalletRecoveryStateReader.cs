namespace Ebir.Mes.Application.PalletRecovery;

public interface IPalletRecoveryStateReader
{
    Task<PalletRecoveryStateRecord?> ReadLatestAsync(
        long lineSessionId,
        CancellationToken cancellationToken);
}
