namespace Ebir.Mes.Application.ProductionWorkstations;

public sealed class GetProductionTableState(IProductionTableStateReader reader)
{
    public Task<ProductionTableStateRecord?> ExecuteAsync(
        long orderId,
        long lineId,
        CancellationToken cancellationToken)
    {
        if (orderId <= 0 || lineId <= 0)
        {
            throw new ArgumentOutOfRangeException(
                orderId <= 0 ? nameof(orderId) : nameof(lineId));
        }

        return reader.ReadAsync(orderId, lineId, cancellationToken);
    }
}
