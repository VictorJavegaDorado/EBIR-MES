namespace Ebir.Mes.Application.Printing;

public sealed record ReprintPalletLabelCommand(
    long PalletId,
    long RequestedBySupervisorId,
    string Reason,
    Guid CorrelationId);
