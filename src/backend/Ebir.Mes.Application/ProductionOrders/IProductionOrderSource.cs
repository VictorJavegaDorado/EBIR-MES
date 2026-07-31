namespace Ebir.Mes.Application.ProductionOrders;

public interface IProductionOrderSource
{
    Task<IReadOnlyList<ProductionOrderRecord>> ReadAsync(
        ProductionOrderStatus status,
        int maximumRecords,
        CancellationToken cancellationToken);
}
