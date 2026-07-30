namespace Ebir.Mes.Api.Endpoints.LineSessions;

public sealed record CorrectCurrentShiftTimeEntryResponse(
    long Id,
    Guid CorrelationId);
