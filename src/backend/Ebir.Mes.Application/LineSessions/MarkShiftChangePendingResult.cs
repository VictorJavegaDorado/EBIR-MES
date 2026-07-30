namespace Ebir.Mes.Application.LineSessions;

public sealed record MarkShiftChangePendingResult(
    ShiftChangePendingOutcome Outcome,
    bool? ChangeMarked,
    string? ErrorCode,
    string? ErrorMessage);
