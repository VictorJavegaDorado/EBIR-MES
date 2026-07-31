namespace Ebir.Mes.Application.ProductionOrders;

public interface IProductionOrderSnapshotStore
{
    Task<ProductionOrderSynchronizationResult> SaveAsync(
        ProductionOrderSnapshot snapshot,
        Guid synchronizationId,
        CancellationToken cancellationToken);
}
