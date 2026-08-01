namespace Ebir.Mes.Application.ProductionOrders;

public interface IProductionOrderSelectionReader
{
    Task<IReadOnlyList<ProductionOrderSelectionRecord>> ReadAsync(
        CancellationToken cancellationToken);
}
