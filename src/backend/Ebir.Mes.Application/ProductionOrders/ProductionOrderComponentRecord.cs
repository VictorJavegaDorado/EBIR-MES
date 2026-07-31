namespace Ebir.Mes.Application.ProductionOrders;

public sealed record ProductionOrderComponentRecord(
    string OrderNumber,
    int ProductionOrderLineNumber,
    int LineNumber,
    ProductionOrderStatus Status,
    string ItemNumber,
    string VariantCode,
    string Description,
    decimal QuantityPer,
    decimal ExpectedQuantity,
    decimal RemainingQuantity,
    decimal ActualConsumptionQuantity,
    string UnitOfMeasureCode,
    ProductionComponentFlushingMethod FlushingMethod,
    string RoutingLinkCode,
    string OperationCode,
    string LocationCode,
    string BinCode,
    decimal QuantityPicked,
    bool SubstitutionAvailable);
