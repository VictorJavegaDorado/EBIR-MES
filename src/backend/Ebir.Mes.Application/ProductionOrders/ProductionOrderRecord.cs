namespace Ebir.Mes.Application.ProductionOrders;

public sealed record ProductionOrderRecord(
    string OrderNumber,
    ProductionOrderStatus Status,
    string Description,
    string ProductNumber,
    string RoutingNumber,
    decimal Quantity,
    string LocationCode,
    DateOnly? StartingDate,
    DateOnly? EndingDate,
    DateOnly? DueDate);
