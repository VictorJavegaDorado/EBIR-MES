namespace Ebir.Mes.Application.LineSessions;

public sealed record MarkShiftChangePendingCommand(
    long LineSessionId,
    Guid CorrelationId);
