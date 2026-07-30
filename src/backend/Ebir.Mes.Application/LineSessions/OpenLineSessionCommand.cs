namespace Ebir.Mes.Application.LineSessions;

public sealed record OpenLineSessionCommand(
    long OrderId, long LineId, long PalletFormatOrderId, long SupervisorId,
    bool OutsideScheduleConfirmed, Guid CorrelationId);
