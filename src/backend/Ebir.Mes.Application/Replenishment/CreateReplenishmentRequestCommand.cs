namespace Ebir.Mes.Application.Replenishment;

public sealed record CreateReplenishmentRequestCommand(
    long LineSessionId,
    long OrderComponentId,
    int RequestedQuantity,
    long RequestedByEmployeeId,
    long? ScrapId,
    Guid CorrelationId);
