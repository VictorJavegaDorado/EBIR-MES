namespace Ebir.Mes.Application.LineSessions;

public sealed record CorrectCurrentShiftTimeEntryCommand(
    long TimeEntryId,
    DateTimeOffset CorrectedEntryUtc,
    DateTimeOffset? CorrectedExitUtc,
    long SupervisorId,
    string Reason,
    Guid CorrelationId);
