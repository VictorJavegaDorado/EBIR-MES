namespace Ebir.Mes.Application.ProductionOrders;

public sealed record ProductionOrderSynchronizationCommand(
    string EnvironmentCode,
    string CompanyCode,
    string OrderNumber,
    Guid SynchronizationId);
