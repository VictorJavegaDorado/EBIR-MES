namespace Ebir.Mes.Api.Endpoints.ProductionOrders;

public sealed record PromoteProductionOrderResponse(
    long ProductionOrderId,
    string Outcome,
    Guid CorrelationId);
