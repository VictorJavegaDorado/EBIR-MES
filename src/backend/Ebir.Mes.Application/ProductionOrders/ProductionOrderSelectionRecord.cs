namespace Ebir.Mes.Application.ProductionOrders;

public sealed record ProductionOrderSelectionRecord(
    long ProductionOrderId,
    string OrderNumber,
    string ProductNumber,
    string ProductDescription,
    string LotNumber,
    int TargetQuantity,
    int GoodQuantity,
    int ReservedQuantity,
    int ScrapQuantity,
    decimal RunTimeMinutes,
    string State,
    DateTime ImportedAtUtc);
