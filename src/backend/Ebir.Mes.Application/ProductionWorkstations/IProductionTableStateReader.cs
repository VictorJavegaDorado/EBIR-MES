namespace Ebir.Mes.Application.ProductionWorkstations;

public interface IProductionTableStateReader
{
    Task<ProductionTableStateRecord?> ReadAsync(
        long orderId,
        long lineId,
        CancellationToken cancellationToken);
}
