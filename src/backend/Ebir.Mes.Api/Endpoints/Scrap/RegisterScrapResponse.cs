namespace Ebir.Mes.Api.Endpoints.Scrap;

public sealed record RegisterScrapResponse(
    long Id,
    long NavOperationId,
    Guid CorrelationId);
