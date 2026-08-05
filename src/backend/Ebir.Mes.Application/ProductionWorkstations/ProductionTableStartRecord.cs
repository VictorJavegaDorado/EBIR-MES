namespace Ebir.Mes.Application.ProductionWorkstations;

public sealed record ProductionTableStartRecord(
    long LineSessionId,
    long TimeEntryId,
    long? PalletReservationId,
    bool SessionCreated);
