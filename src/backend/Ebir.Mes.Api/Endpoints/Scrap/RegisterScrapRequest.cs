namespace Ebir.Mes.Api.Endpoints.Scrap;

public sealed record RegisterScrapRequest(
    long OrderComponentId,
    short ScrapReasonId,
    int Quantity,
    string? Description,
    long RegisteredByEmployeeId,
    Guid CorrelationId);
