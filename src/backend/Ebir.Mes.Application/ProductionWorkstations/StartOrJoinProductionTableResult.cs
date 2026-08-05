namespace Ebir.Mes.Application.ProductionWorkstations;

public sealed record StartOrJoinProductionTableResult(
    StartOrJoinProductionTableOutcome Outcome,
    ProductionTableStartRecord? Start,
    string? ErrorCode,
    string? ErrorMessage);
