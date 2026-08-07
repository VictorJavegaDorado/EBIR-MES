namespace Ebir.Mes.Application.ProductionWorkstations;

public sealed record CompleteProductionOrderResult(
    CompleteProductionOrderOutcome Outcome,
    string? ErrorCode,
    string? ErrorMessage);
