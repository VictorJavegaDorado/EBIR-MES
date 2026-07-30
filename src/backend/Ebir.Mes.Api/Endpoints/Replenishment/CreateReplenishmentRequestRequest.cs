namespace Ebir.Mes.Api.Endpoints.Replenishment;

public sealed record CreateReplenishmentRequestRequest(
    long OrderComponentId,
    int RequestedQuantity,
    long RequestedByEmployeeId,
    long? ScrapId,
    Guid CorrelationId);
