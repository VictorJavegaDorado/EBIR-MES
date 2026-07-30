namespace Ebir.Mes.Application.LineSessions;

public sealed class RegisterProductiveEntry(IProductiveEntryRegistrar registrar)
{
    public async Task<RegisterProductiveEntryResult> ExecuteAsync(
        RegisterProductiveEntryCommand command,
        CancellationToken cancellationToken)
    {
        var validation = Validate(command);
        if (validation is not null)
        {
            return validation;
        }

        try
        {
            var entry = await registrar.RegisterAsync(command, cancellationToken);
            return new(ProductiveEntryOutcome.Registered, entry, null, null);
        }
        catch (LineSessionRejectedException exception)
        {
            return new(
                ProductiveEntryOutcome.Rejected,
                null,
                exception.ErrorCode,
                exception.Message);
        }
    }

    private static RegisterProductiveEntryResult? Validate(
        RegisterProductiveEntryCommand command)
    {
        if (command.LineSessionId <= 0)
        {
            return Invalid(
                "LINE_SESSION_ID_INVALID",
                "sessionId debe ser un identificador positivo.");
        }

        if (command.EmployeeId <= 0)
        {
            return Invalid(
                "EMPLOYEE_ID_INVALID",
                "employeeId debe ser un identificador positivo.");
        }

        return command.CorrelationId == Guid.Empty
            ? Invalid(
                "CORRELATION_ID_INVALID",
                "correlationId debe ser un UUID distinto de cero.")
            : null;
    }

    private static RegisterProductiveEntryResult Invalid(
        string code,
        string message)
    {
        return new(ProductiveEntryOutcome.InvalidRequest, null, code, message);
    }
}
