namespace Ebir.Mes.Api.Endpoints.LineSessions;

public sealed record OpenLineSessionRequest(
    long OrderId,
    long LineId,
    long PalletFormatOrderId,
    long SupervisorId,
    bool OutsideScheduleConfirmed,
    Guid CorrelationId);
