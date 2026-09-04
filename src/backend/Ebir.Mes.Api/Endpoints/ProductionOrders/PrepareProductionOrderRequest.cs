namespace Ebir.Mes.Api.Endpoints.ProductionOrders;

public sealed record PrepareProductionOrderRequest(
    string OrderNumber,
    Guid CorrelationId);
