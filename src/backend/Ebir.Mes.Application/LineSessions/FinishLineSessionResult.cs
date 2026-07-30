namespace Ebir.Mes.Application.LineSessions;

public sealed record FinishLineSessionResult(
    FinishLineSessionOutcome Outcome,
    int? ClosedTimeEntries,
    string? ErrorCode,
    string? ErrorMessage);
