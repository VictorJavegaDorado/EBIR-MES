namespace Ebir.Mes.Application.ProductionOrders;

public sealed record ProductionOrderPromotionResult(
    long ProductionOrderId,
    ProductionOrderPromotionOutcome Outcome);
