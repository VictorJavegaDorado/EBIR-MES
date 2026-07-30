namespace Ebir.Mes.Application.Replenishment;

public sealed record TransitionReplenishmentRequestCommand(
    long RequestId,
    string NewState,
    long EmployeeId,
    string? Comment,
    Guid CorrelationId);
