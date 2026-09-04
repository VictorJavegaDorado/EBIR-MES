namespace Ebir.Mes.Application.ProductionOrders;

public sealed record PrepareProductionOrderResult(
    ProductionOrderSelectionRecord Order,
    ProductionOrderSynchronizationOutcome SynchronizationOutcome,
    ProductionOrderPromotionOutcome PromotionOutcome);
