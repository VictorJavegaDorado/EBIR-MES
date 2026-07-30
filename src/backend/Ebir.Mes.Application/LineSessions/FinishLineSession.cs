namespace Ebir.Mes.Application.LineSessions;

public sealed class FinishLineSession(ILineSessionFinisher finisher)
{
    public async Task<FinishLineSessionResult> ExecuteAsync(
        FinishLineSessionCommand command,
        CancellationToken cancellationToken)
    {
        if (command.LineSessionId <= 0)
        {
            return Invalid("LINE_SESSION_ID_INVALID",
                "sessionId debe ser un identificador positivo.");
        }

        if (command.SupervisorId <= 0)
        {
            return Invalid("SUPERVISOR_ID_INVALID",
                "supervisorId debe ser un identificador positivo.");
        }

        if (command.CorrelationId == Guid.Empty)
        {
            return Invalid("CORRELATION_ID_INVALID",
                "correlationId debe ser un UUID distinto de cero.");
        }

        try
        {
            var closed = await finisher.FinishAsync(command, cancellationToken);
            return new(FinishLineSessionOutcome.Finished, closed, null, null);
        }
        catch (LineSessionRejectedException exception)
        {
            return new(
                FinishLineSessionOutcome.Rejected,
                null,
                exception.ErrorCode,
                exception.Message);
        }
    }

    private static FinishLineSessionResult Invalid(string code, string message) =>
        new(FinishLineSessionOutcome.InvalidRequest, null, code, message);
}
