namespace Ebir.Mes.Application.ProductionOrders;

public sealed record ProductionOrderSynchronizationResult(
    long InboundOrderId,
    ProductionOrderSynchronizationOutcome Outcome);
