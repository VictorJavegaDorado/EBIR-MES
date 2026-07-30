namespace Ebir.Mes.Api.Endpoints.Pallets;

public sealed record ClosePalletRequest(
    int GoodQuantity,
    long ClosedByEmployeeId,
    long? AuthorizingSupervisorId,
    bool IsPartial,
    string? PartialReason,
    Guid CorrelationId);
