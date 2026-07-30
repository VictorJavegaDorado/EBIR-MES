namespace Ebir.Mes.Application.LineSessions;

public sealed record RegisterProductiveExitResult(
    ProductiveExitOutcome Outcome,
    int? ActiveResources,
    string? ErrorCode,
    string? ErrorMessage);
