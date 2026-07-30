namespace Ebir.Mes.Api.Endpoints.Replenishment;

public sealed record TransitionReplenishmentRequestRequest(
    string NewState,
    long EmployeeId,
    string? Comment,
    Guid CorrelationId);
