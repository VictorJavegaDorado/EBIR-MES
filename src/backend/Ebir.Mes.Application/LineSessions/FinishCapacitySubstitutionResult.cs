namespace Ebir.Mes.Application.LineSessions;

public sealed record FinishCapacitySubstitutionResult(
    FinishCapacitySubstitutionOutcome Outcome,
    int? ActiveResources,
    string? ErrorCode,
    string? ErrorMessage);
