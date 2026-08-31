namespace Ebir.Mes.Api.Endpoints.Printing;

public sealed record ReprintPalletLabelRequest(
    long RequestedBySupervisorId,
    string Reason,
    Guid CorrelationId);
