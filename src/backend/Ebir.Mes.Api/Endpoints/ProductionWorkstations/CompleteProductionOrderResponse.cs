namespace Ebir.Mes.Api.Endpoints.ProductionWorkstations;

public sealed record CompleteProductionOrderResponse(
    string State,
    Guid CorrelationId);
