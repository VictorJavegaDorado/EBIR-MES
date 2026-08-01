namespace Ebir.Mes.Application.ProductionOrders;

public sealed record ProductionOrderLotRecord(
    string OrderNumber,
    string ProductNumber,
    string LotNumber);
