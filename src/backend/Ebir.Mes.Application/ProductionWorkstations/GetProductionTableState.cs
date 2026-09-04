using Ebir.Mes.Application.PalletRecovery;

namespace Ebir.Mes.Application.ProductionWorkstations;

public sealed class GetProductionTableState(
    IProductionTableStateReader reader,
    IPalletRecoveryStateReader? recoveryReader = null)
{
    public async Task<ProductionTableStateRecord?> ExecuteAsync(
        long orderId,
        long lineId,
        CancellationToken cancellationToken)
    {
        if (orderId <= 0 || lineId <= 0)
        {
            throw new ArgumentOutOfRangeException(
                orderId <= 0 ? nameof(orderId) : nameof(lineId));
        }

        var state = await reader.ReadAsync(orderId, lineId, cancellationToken);
        if (state is null || recoveryReader is null) return state;
        var recovery = await recoveryReader.ReadLatestAsync(
            state.LineSessionId, cancellationToken);
        return state with { LatestPalletRecovery = recovery };
    }
}
