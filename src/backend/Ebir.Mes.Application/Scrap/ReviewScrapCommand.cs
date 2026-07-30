namespace Ebir.Mes.Application.Scrap;

public sealed record ReviewScrapCommand(
    long ScrapId,
    long OrderComponentId,
    short ScrapReasonId,
    int Quantity,
    string? Description,
    bool IsCancellation,
    long AdjustedBySupervisorId,
    string AdjustmentReason,
    Guid CorrelationId);
