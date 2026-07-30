namespace Ebir.Mes.Api.Endpoints.LineSessions;

public sealed record CorrectCurrentShiftTimeEntryRequest(
    DateTimeOffset CorrectedEntryUtc,
    DateTimeOffset? CorrectedExitUtc,
    long SupervisorId,
    string Reason,
    Guid CorrelationId);
