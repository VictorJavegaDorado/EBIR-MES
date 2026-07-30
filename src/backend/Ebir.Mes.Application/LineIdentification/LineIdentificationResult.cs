namespace Ebir.Mes.Application.LineIdentification;

public sealed record LineIdentificationResult(
    LineIdentificationOutcome Outcome,
    string NormalizedCode,
    LineIdentificationRecord? Line,
    string? ErrorCode,
    string? ErrorMessage);

