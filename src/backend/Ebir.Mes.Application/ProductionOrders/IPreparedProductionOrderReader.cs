namespace Ebir.Mes.Application.ProductionOrders;

public interface IPreparedProductionOrderReader
{
    Task<ProductionOrderSelectionRecord?> ReadAsync(
        long productionOrderId,
        CancellationToken cancellationToken);
}
