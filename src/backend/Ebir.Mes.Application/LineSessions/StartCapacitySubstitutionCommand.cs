namespace Ebir.Mes.Application.LineSessions;

public sealed record StartCapacitySubstitutionCommand(
    long LineSessionId,
    long ReplacedOperatorId,
    long SubstituteSupervisorId,
    string Reason,
    Guid CorrelationId);
