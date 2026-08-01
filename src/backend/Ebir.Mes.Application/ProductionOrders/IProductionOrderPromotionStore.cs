namespace Ebir.Mes.Application.ProductionOrders;

public interface IProductionOrderPromotionStore
{
    Task<ProductionOrderPromotionResult> PromoteAsync(
        ProductionOrderPromotionCommand command,
        CancellationToken cancellationToken);
}
