namespace Ebir.Mes.Application.ProductionOrders;

public sealed record PrepareProductionOrderCommand(
    string EnvironmentCode,
    string CompanyCode,
    string OrderNumber,
    Guid CorrelationId);
