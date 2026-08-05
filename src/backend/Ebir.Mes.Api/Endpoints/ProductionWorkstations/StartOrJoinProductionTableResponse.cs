namespace Ebir.Mes.Api.Endpoints.ProductionWorkstations;

public sealed record StartOrJoinProductionTableResponse(
    long LineSessionId,
    long TimeEntryId,
    long? PalletReservationId,
    bool SessionCreated,
    Guid CorrelationId);
