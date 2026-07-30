namespace Ebir.Mes.Api.Endpoints.LineSessions;

public sealed record StartCapacitySubstitutionRequest(
    long ReplacedOperatorId,
    long SubstituteSupervisorId,
    string Reason,
    Guid CorrelationId);
