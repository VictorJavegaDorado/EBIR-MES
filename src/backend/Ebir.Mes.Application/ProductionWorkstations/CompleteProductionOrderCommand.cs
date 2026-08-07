namespace Ebir.Mes.Application.ProductionWorkstations;

public sealed record CompleteProductionOrderCommand(
    long LineSessionId,
    Guid CorrelationId);
