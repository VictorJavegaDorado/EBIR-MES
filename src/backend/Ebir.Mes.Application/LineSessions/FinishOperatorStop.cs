namespace Ebir.Mes.Application.LineSessions;

public sealed class FinishOperatorStop(IOperatorStopFinisher finisher)
{
    public async Task<FinishOperatorStopResult> ExecuteAsync(
        FinishOperatorStopCommand command, CancellationToken cancellationToken)
    {
        if (command.LineSessionId <= 0) return Invalid("LINE_SESSION_ID_INVALID");
        if (command.EmployeeId <= 0) return Invalid("EMPLOYEE_ID_INVALID");
        if (command.CorrelationId == Guid.Empty) return Invalid("CORRELATION_ID_INVALID");
        try
        {
            return new(FinishOperatorStopOutcome.Finished,
                await finisher.FinishAsync(command, cancellationToken), null, null);
        }
        catch (LineSessionRejectedException exception)
        {
            return new(FinishOperatorStopOutcome.Rejected, null,
                exception.ErrorCode, exception.Message);
        }
    }

    private static FinishOperatorStopResult Invalid(string code) =>
        new(FinishOperatorStopOutcome.InvalidRequest, null, code,
            "La solicitud de retorno del paro no es válida.");
}
