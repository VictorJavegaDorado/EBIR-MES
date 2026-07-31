namespace Ebir.Mes.Api.Endpoints.ProductionOrders;

public sealed record SynchronizeProductionOrderResponse(
    long InboundOrderId,
    string Outcome,
    Guid CorrelationId);
