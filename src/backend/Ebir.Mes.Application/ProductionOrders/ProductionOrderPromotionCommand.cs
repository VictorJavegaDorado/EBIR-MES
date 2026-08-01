namespace Ebir.Mes.Application.ProductionOrders;

public sealed record ProductionOrderPromotionCommand(
    long InboundOrderId,
    string OperationNumber,
    Guid CorrelationId);
