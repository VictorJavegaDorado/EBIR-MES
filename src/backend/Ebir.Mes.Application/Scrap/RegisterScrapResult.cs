namespace Ebir.Mes.Application.Scrap;

public sealed record RegisterScrapResult(
    RegisterScrapOutcome Outcome,
    RegisteredScrapRecord? Scrap,
    string? ErrorCode,
    string? ErrorMessage);
