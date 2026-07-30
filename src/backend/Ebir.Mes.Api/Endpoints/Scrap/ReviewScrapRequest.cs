namespace Ebir.Mes.Api.Endpoints.Scrap;

public sealed record ReviewScrapRequest(
    long OrderComponentId,
    short ScrapReasonId,
    int Quantity,
    string? Description,
    bool IsCancellation,
    long AdjustedBySupervisorId,
    string AdjustmentReason,
    Guid CorrelationId);
