namespace Ebir.Mes.Application.LineSessions;

public sealed class StartOperatorStop(IOperatorStopStarter starter)
{
    public async Task<StartOperatorStopResult> ExecuteAsync(
        StartOperatorStopCommand command, CancellationToken cancellationToken)
    {
        var reason = command.Reason?.Trim().ToUpperInvariant() ?? string.Empty;
        if (command.LineSessionId <= 0) return Invalid("LINE_SESSION_ID_INVALID");
        if (command.EmployeeId <= 0) return Invalid("EMPLOYEE_ID_INVALID");
        if (reason is not ("WC" or "PAUSA_CALOR")) return Invalid("STOP_REASON_INVALID");
        if (command.CorrelationId == Guid.Empty) return Invalid("CORRELATION_ID_INVALID");
        try
        {
            var normalized = command with { Reason = reason };
            return new(StartOperatorStopOutcome.Started,
                await starter.StartAsync(normalized, cancellationToken), null, null);
        }
        catch (LineSessionRejectedException exception)
        {
            return new(StartOperatorStopOutcome.Rejected, null,
                exception.ErrorCode, exception.Message);
        }
    }

    private static StartOperatorStopResult Invalid(string code) =>
        new(StartOperatorStopOutcome.InvalidRequest, null, code,
            "La solicitud de paro de operario no es válida.");
}
