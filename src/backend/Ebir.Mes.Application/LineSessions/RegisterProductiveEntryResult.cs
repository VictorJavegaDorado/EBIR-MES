namespace Ebir.Mes.Application.LineSessions;

public sealed record RegisterProductiveEntryResult(
    ProductiveEntryOutcome Outcome,
    ProductiveEntryRecord? Entry,
    string? ErrorCode,
    string? ErrorMessage);
