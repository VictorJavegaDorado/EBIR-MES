namespace Ebir.Mes.Application.LineSessions;

public sealed record StartOperatorStopResult(
    StartOperatorStopOutcome Outcome, OperatorStopRecord? Stop,
    string? ErrorCode, string? ErrorMessage);
