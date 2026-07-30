namespace Ebir.Mes.Application.Replenishment;

public sealed record TransitionReplenishmentRequestResult(
    TransitionReplenishmentRequestOutcome Outcome,
    string? State,
    string? ErrorCode,
    string? ErrorMessage);
