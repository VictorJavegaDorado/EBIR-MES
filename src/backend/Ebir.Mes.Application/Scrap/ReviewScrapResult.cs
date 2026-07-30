namespace Ebir.Mes.Application.Scrap;

public sealed record ReviewScrapResult(
    ReviewScrapOutcome Outcome,
    ReviewedScrapRecord? Revision,
    string? ErrorCode,
    string? ErrorMessage);
