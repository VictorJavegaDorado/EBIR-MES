namespace Ebir.Mes.Api.Endpoints.LineSessions;

public sealed record FinishCapacitySubstitutionResponse(
    long Id, int ActiveResources, Guid CorrelationId);
