namespace Ebir.Mes.Api.Endpoints.LineSessions;

public sealed record StartOperatorStopResponse(
    long Id, int ActiveResources, Guid CorrelationId);
