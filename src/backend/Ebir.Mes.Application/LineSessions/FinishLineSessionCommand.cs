namespace Ebir.Mes.Application.LineSessions;

public sealed record FinishLineSessionCommand(
    long LineSessionId,
    long SupervisorId,
    Guid CorrelationId);
