namespace Ebir.Mes.Application.ProductionOrders;

public sealed record ProductionOrderPalletFormatRecord(
    string ProductNumber,
    string Code,
    decimal QuantityPerUnitMeasure);
