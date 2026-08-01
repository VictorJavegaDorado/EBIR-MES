namespace Ebir.Mes.Api.Endpoints.ProductionOrders;

public sealed record PromoteProductionOrderRequest(
    long InboundOrderId,
    string OperationNumber,
    Guid CorrelationId);
