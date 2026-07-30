namespace Ebir.Mes.Api.Endpoints.Replenishment;

public sealed record CreateReplenishmentRequestResponse(
    long Id,
    string State,
    long? ScrapId,
    Guid CorrelationId);
