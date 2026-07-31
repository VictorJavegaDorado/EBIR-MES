namespace Ebir.Mes.Application.ProductionOrders;

public sealed record ProductionOrderLineRecord(
    string OrderNumber,
    ProductionOrderStatus Status,
    string ProductNumber,
    string VariantCode,
    string Description,
    string LocationCode,
    decimal Quantity,
    decimal FinishedQuantity,
    decimal RemainingQuantity,
    decimal ScrapPercent,
    DateOnly? DueDate,
    DateOnly? StartingDate,
    DateOnly? EndingDate,
    string ProductionBomNumber);
