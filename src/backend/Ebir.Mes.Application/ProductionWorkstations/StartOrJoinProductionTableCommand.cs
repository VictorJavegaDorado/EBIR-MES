namespace Ebir.Mes.Application.ProductionWorkstations;

public sealed record StartOrJoinProductionTableCommand(
    long OrderId,
    long LineId,
    long EmployeeId,
    Guid CorrelationId);
