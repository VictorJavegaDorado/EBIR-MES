namespace Ebir.Mes.Api.Endpoints.LineSessions;

public sealed record MarkShiftChangePendingResponse(
    bool ChangeMarked,
    Guid CorrelationId);
