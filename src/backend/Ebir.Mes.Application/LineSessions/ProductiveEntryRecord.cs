namespace Ebir.Mes.Application.LineSessions;

public sealed record ProductiveEntryRecord(
    long TimeEntryId,
    long? PalletReservationId);
