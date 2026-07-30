namespace Ebir.Mes.Application.LineSessions;

public sealed record StartOperatorStopCommand(
    long LineSessionId, long EmployeeId, string Reason, Guid CorrelationId);
