namespace Ebir.Mes.Api.Endpoints.ProductionOrders;

public sealed record ProductionOrderSelectionResponse(
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
