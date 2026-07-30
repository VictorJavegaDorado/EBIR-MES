namespace Ebir.Mes.Application.Scrap;

public sealed record RegisterScrapCommand(
    long LineSessionId,
    long OrderComponentId,
    short ScrapReasonId,
    int Quantity,
    string? Description,
    long RegisteredByEmployeeId,
    Guid CorrelationId);
