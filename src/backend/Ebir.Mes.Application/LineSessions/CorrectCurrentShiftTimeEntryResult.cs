namespace Ebir.Mes.Application.LineSessions;

public sealed record CorrectCurrentShiftTimeEntryResult(
    CorrectCurrentShiftTimeEntryOutcome Outcome,
    string? ErrorCode,
    string? ErrorMessage);
