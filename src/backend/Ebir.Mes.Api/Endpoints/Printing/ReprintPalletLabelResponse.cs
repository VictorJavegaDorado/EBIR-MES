namespace Ebir.Mes.Api.Endpoints.Printing;

public sealed record ReprintPalletLabelResponse(
    long Id,
    long PalletId,
    Guid CorrelationId);
