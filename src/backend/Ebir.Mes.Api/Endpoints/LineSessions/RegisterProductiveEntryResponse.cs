namespace Ebir.Mes.Api.Endpoints.LineSessions;

public sealed record RegisterProductiveEntryResponse(
    long Id,
    long? PalletReservationId,
    Guid CorrelationId);
