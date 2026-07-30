namespace Ebir.Mes.Application.Pallets.ClosePallet;

public sealed record ClosePalletCommand(
    long ReservationId,
    int GoodQuantity,
    long ClosedByEmployeeId,
    long? AuthorizingSupervisorId,
    bool IsPartial,
    string? PartialReason,
    Guid CorrelationId);
