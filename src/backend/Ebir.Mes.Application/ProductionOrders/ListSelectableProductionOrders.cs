namespace Ebir.Mes.Application.ProductionOrders;

public sealed class ListSelectableProductionOrders(
    IProductionOrderSelectionReader reader)
{
    public Task<IReadOnlyList<ProductionOrderSelectionRecord>> ExecuteAsync(
        CancellationToken cancellationToken) =>
        reader.ReadAsync(cancellationToken);
}
