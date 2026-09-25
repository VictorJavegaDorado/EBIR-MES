using Ebir.Mes.Application.PalletRecovery;
using Ebir.Mes.Application.Replenishment;

namespace Ebir.Mes.Application.ProductionWorkstations;

public sealed class GetActiveProductionTable(
    IProductionTableStateReader reader,
    IPalletRecoveryStateReader? recoveryReader = null,
    GetProductionMaterialRequestStatuses? materialStatuses = null)
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
        if (active is null) return null;
        var table = active.Table;
        if (recoveryReader is not null)
        {
            try
            {
                var recovery = await recoveryReader.ReadLatestAsync(
                    table.LineSessionId, cancellationToken);
                table = table with { LatestPalletRecovery = recovery };
            }
            catch (PalletRecoveryUnavailableException) { }
        }
        if (materialStatuses is not null)
        {
            try
            {
                var requests = await materialStatuses.ExecuteAsync(
                    table.LineSessionId, cancellationToken);
                table = table with { MaterialRequests = requests };
            }
            catch (MaterialRequestUnavailableException) { }
        }
        return active with { Table = table };
    }
}
