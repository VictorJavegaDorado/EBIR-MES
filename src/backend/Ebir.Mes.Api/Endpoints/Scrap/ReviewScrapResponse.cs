namespace Ebir.Mes.Api.Endpoints.Scrap;

public sealed record ReviewScrapResponse(
    long Id,
    long ScrapId,
    long NavOperationId,
    bool IsCancellation,
    Guid CorrelationId);
