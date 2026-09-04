using Ebir.Mes.Application.PalletRecovery;

namespace Ebir.Mes.Application.ProductionWorkstations;

public sealed class GetActiveProductionTable(
    IProductionTableStateReader reader,
    IPalletRecoveryStateReader? recoveryReader = null)
{
    public async Task<ActiveProductionTableRecord?> ExecuteAsync(
        long lineId,
        CancellationToken cancellationToken)
    {
        if (lineId <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(lineId));
        }

        var active = await reader.ReadActiveByLineAsync(lineId, cancellationToken);
        if (active is null || recoveryReader is null) return active;
        var recovery = await recoveryReader.ReadLatestAsync(
            active.Table.LineSessionId, cancellationToken);
        return active with
        {
            Table = active.Table with { LatestPalletRecovery = recovery }
        };
    }
}
