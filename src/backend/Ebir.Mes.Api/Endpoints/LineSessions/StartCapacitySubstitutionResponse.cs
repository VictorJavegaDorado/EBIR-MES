namespace Ebir.Mes.Api.Endpoints.LineSessions;

public sealed record StartCapacitySubstitutionResponse(
    long Id,
    long SupervisorTimeEntryId,
    int ActiveResources,
    Guid CorrelationId);
