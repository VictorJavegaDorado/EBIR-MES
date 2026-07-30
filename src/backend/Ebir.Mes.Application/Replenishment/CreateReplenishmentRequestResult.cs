namespace Ebir.Mes.Application.Replenishment;

public sealed record CreateReplenishmentRequestResult(
    CreateReplenishmentRequestOutcome Outcome,
    long? RequestId,
    string? ErrorCode,
    string? ErrorMessage);
