namespace Ebir.Mes.Api.Endpoints.LineSessions;

public sealed record FinishCapacitySubstitutionRequest(
    long SupervisorId, string Reason, Guid CorrelationId);
