namespace Ebir.Mes.Api.Endpoints.ProductionOrders;

public sealed record PromoteProductionOrderRequest(
    long InboundOrderId,
    string Lot,
    string OperationNumber,
    string LotProvidedBy,
    Guid CorrelationId);
