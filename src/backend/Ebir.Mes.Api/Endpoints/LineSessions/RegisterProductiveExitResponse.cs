namespace Ebir.Mes.Api.Endpoints.LineSessions;

public sealed record RegisterProductiveExitResponse(
    int ActiveResources,
    Guid CorrelationId);
