namespace Ebir.Mes.Application.LineSessions;

public sealed class OpenLineSession(ILineSessionOpener opener)
{
    public async Task<OpenLineSessionResult> ExecuteAsync(
        OpenLineSessionCommand command,
        CancellationToken cancellationToken)
    {
        var validation = Validate(command);
        if (validation is not null)
        {
            return validation;
        }

        try
        {
            var sessionId = await opener.OpenAsync(command, cancellationToken);
            return new(OpenLineSessionOutcome.Opened, sessionId, null, null);
        }
        catch (LineSessionRejectedException exception)
        {
            return new(
                OpenLineSessionOutcome.Rejected,
                null,
                exception.ErrorCode,
                exception.Message);
        }
    }

    private static OpenLineSessionResult? Validate(OpenLineSessionCommand command)
    {
        if (command.OrderId <= 0)
        {
            return Invalid("ORDER_ID_INVALID", "orderId debe ser un identificador positivo.");
        }

        if (command.LineId <= 0)
        {
            return Invalid("LINE_ID_INVALID", "lineId debe ser un identificador positivo.");
        }

        if (command.PalletFormatOrderId <= 0)
        {
            return Invalid(
                "PALLET_FORMAT_ORDER_ID_INVALID",
                "palletFormatOrderId debe ser un identificador positivo.");
        }

        if (command.SupervisorId <= 0)
        {
            return Invalid(
                "SUPERVISOR_ID_INVALID",
                "supervisorId debe ser un identificador positivo.");
        }

        return command.CorrelationId == Guid.Empty
            ? Invalid(
                "CORRELATION_ID_INVALID",
                "correlationId debe ser un UUID distinto de cero.")
            : null;
    }

    private static OpenLineSessionResult Invalid(string code, string message)
    {
        return new(OpenLineSessionOutcome.InvalidRequest, null, code, message);
    }
}
