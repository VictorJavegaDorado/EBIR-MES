namespace Ebir.Mes.Api.Endpoints.Replenishment;

public sealed record TransitionReplenishmentRequestResponse(
    long Id,
    string State,
    Guid CorrelationId);
