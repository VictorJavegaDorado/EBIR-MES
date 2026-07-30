namespace Ebir.Mes.Api.Endpoints.LineSessions;

public sealed record FinishLineSessionRequest(
    long SupervisorId,
    Guid CorrelationId);
