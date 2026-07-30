namespace Ebir.Mes.Application.LineSessions;

public sealed record FinishOperatorStopResult(
    FinishOperatorStopOutcome Outcome, FinishedOperatorStopRecord? Stop,
    string? ErrorCode, string? ErrorMessage);
