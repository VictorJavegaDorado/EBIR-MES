namespace Ebir.Mes.Application.LineSessions;

public sealed record RegisterProductiveEntryCommand(
    long LineSessionId,
    long EmployeeId,
    Guid CorrelationId);
