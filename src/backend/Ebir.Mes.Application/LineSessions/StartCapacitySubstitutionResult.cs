namespace Ebir.Mes.Application.LineSessions;

public sealed record StartCapacitySubstitutionResult(
    StartCapacitySubstitutionOutcome Outcome,
    CapacitySubstitutionRecord? Substitution,
    string? ErrorCode,
    string? ErrorMessage);
