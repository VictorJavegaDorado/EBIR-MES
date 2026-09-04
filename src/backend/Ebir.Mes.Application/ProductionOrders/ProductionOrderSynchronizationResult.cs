namespace Ebir.Mes.Application.ProductionOrders;

public sealed record ProductionOrderSynchronizationResult(
    long InboundOrderId,
    ProductionOrderSynchronizationOutcome Outcome)
{
    public string PaternaOperationNumber { get; init; } = string.Empty;
}
