using Ebir.Mes.Application.PalletRecovery;
using Ebir.Mes.Application.Replenishment;

namespace Ebir.Mes.Application.ProductionWorkstations;

public sealed class GetProductionTableState(
    IProductionTableStateReader reader,
    IPalletRecoveryStateReader? recoveryReader = null,
    GetProductionMaterialRequestStatuses? materialStatuses = null)
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
        if (state is null) return null;
        if (recoveryReader is not null)
        {
            try
            {
                var recovery = await recoveryReader.ReadLatestAsync(
                    state.LineSessionId, cancellationToken);
                state = state with { LatestPalletRecovery = recovery };
            }
            catch (PalletRecoveryUnavailableException) { }
        }
        if (materialStatuses is not null)
        {
            try
            {
                var requests = await materialStatuses.ExecuteAsync(
                    state.LineSessionId, cancellationToken);
                state = state with { MaterialRequests = requests };
            }
            catch (MaterialRequestUnavailableException) { }
        }
        return state;
    }
}
