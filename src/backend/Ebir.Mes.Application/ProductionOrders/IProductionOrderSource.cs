namespace Ebir.Mes.Application.ProductionOrders;

public interface IProductionOrderSource
{
    Task<IReadOnlyList<ProductionOrderRecord>> ReadAsync(
        ProductionOrderStatus status,
        int maximumRecords,
        CancellationToken cancellationToken);

    Task<IReadOnlyList<ProductionOrderLineRecord>> ReadLinesAsync(
        ProductionOrderStatus status,
        string orderNumber,
        int maximumRecords,
        CancellationToken cancellationToken);

    Task<IReadOnlyList<ProductionOrderRoutingStepRecord>> ReadRoutingAsync(
        string orderNumber,
        int maximumRecords,
        CancellationToken cancellationToken);

    Task<IReadOnlyList<ProductionOrderComponentRecord>> ReadComponentsAsync(
        ProductionOrderStatus status,
        string orderNumber,
        int maximumRecords,
        CancellationToken cancellationToken);
}
