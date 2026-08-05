namespace Ebir.Mes.Api.Endpoints.ProductionWorkstations;

public sealed record StartOrJoinProductionTableRequest(
    long OrderId,
    long LineId,
    long EmployeeId,
    Guid CorrelationId);
