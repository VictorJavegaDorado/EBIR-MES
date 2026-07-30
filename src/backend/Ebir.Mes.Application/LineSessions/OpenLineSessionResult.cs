namespace Ebir.Mes.Application.LineSessions;

public sealed record OpenLineSessionResult(
    OpenLineSessionOutcome Outcome,
    long? LineSessionId,
    string? ErrorCode,
    string? ErrorMessage);
