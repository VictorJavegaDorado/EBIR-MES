namespace Ebir.Mes.Application.LineSessions;

public sealed record RegisterProductiveExitCommand(
    long LineSessionId,
    long EmployeeId,
    Guid CorrelationId);
