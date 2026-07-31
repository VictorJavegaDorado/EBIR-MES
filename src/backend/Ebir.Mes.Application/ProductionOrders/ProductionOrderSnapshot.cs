namespace Ebir.Mes.Application.ProductionOrders;

public sealed record ProductionOrderSnapshot(
    string EnvironmentCode,
    string CompanyCode,
    ProductionOrderRecord Order,
    ProductionOrderLineRecord Line,
    IReadOnlyList<ProductionOrderRoutingStepRecord> Routing,
    IReadOnlyList<ProductionOrderComponentRecord> Components);
