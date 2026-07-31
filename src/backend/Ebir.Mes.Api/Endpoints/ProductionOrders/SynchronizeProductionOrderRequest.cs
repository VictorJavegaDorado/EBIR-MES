namespace Ebir.Mes.Api.Endpoints.ProductionOrders;

public sealed record SynchronizeProductionOrderRequest(
    string OrderNumber,
    Guid CorrelationId);
