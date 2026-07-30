namespace Ebir.Mes.Application.LineSessions;

public sealed record FinishCapacitySubstitutionCommand(
    long CapacitySubstitutionId,
    long SupervisorId,
    string Reason,
    Guid CorrelationId);
