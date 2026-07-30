namespace Ebir.Mes.Application.LineSessions;

public sealed record FinishOperatorStopCommand(
    long LineSessionId, long EmployeeId, Guid CorrelationId);
