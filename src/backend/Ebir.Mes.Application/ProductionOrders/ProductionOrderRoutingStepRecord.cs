namespace Ebir.Mes.Application.ProductionOrders;

public sealed record ProductionOrderRoutingStepRecord(
    string OrderNumber,
    int RoutingReferenceNumber,
    string RoutingNumber,
    string OperationNumber,
    string PreviousOperationNumber,
    string NextOperationNumber,
    ProductionRoutingStepType Type,
    string CapacityNumber,
    string Description,
    DateTime? StartingAt,
    DateTime? EndingAt,
    decimal SetupTime,
    decimal RunTime,
    decimal WaitTime,
    decimal MoveTime,
    decimal FixedScrapQuantity,
    string RoutingLinkCode,
    decimal ScrapFactorPercent,
    ProductionRoutingStatus Status,
    string LocationCode,
    bool IsSigning);
