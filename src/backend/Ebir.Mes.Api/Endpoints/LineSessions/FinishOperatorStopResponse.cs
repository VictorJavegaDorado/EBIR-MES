namespace Ebir.Mes.Api.Endpoints.LineSessions;

public sealed record FinishOperatorStopResponse(
    long Id, long? FinishedSubstitutionId, int ActiveResources, Guid CorrelationId);
