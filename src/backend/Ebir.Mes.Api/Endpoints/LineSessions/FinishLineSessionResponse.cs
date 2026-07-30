namespace Ebir.Mes.Api.Endpoints.LineSessions;

public sealed record FinishLineSessionResponse(
    int ClosedTimeEntries,
    Guid CorrelationId);
