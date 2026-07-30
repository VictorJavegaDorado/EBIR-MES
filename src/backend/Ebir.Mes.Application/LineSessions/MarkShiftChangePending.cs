namespace Ebir.Mes.Application.LineSessions;

public sealed class MarkShiftChangePending(IShiftChangePendingMarker marker)
{
    public async Task<MarkShiftChangePendingResult> ExecuteAsync(
        MarkShiftChangePendingCommand command,
        CancellationToken cancellationToken)
    {
        if (command.LineSessionId <= 0)
        {
            return Invalid(
                "LINE_SESSION_ID_INVALID",
                "sessionId debe ser un identificador positivo.");
        }

        if (command.CorrelationId == Guid.Empty)
        {
            return Invalid(
                "CORRELATION_ID_INVALID",
                "correlationId debe ser un UUID distinto de cero.");
        }

        try
        {
            var changeMarked = await marker.MarkAsync(command, cancellationToken);
            return new(
                ShiftChangePendingOutcome.Processed,
                changeMarked,
                null,
                null);
        }
        catch (LineSessionRejectedException exception)
        {
            return new(
                ShiftChangePendingOutcome.Rejected,
                null,
                exception.ErrorCode,
                exception.Message);
        }
    }

    private static MarkShiftChangePendingResult Invalid(
        string code,
        string message) =>
        new(ShiftChangePendingOutcome.InvalidRequest, null, code, message);
}
