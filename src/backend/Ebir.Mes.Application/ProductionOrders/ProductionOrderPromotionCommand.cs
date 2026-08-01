namespace Ebir.Mes.Application.ProductionOrders;

public sealed record ProductionOrderPromotionCommand(
    long InboundOrderId,
    string Lot,
    string OperationNumber,
    string LotProvidedBy,
    Guid CorrelationId);
