namespace Ebir.Mes.Application.LineSessions;

public sealed class RegisterProductiveExit(IProductiveExitRegistrar registrar)
{
    public async Task<RegisterProductiveExitResult> ExecuteAsync(
        RegisterProductiveExitCommand command,
        CancellationToken cancellationToken)
    {
        var validation = Validate(command);
        if (validation is not null)
        {
            return validation;
        }

        try
        {
            var activeResources = await registrar.RegisterAsync(
                command,
                cancellationToken);
            return new(ProductiveExitOutcome.Registered, activeResources, null, null);
        }
        catch (LineSessionRejectedException exception)
        {
            return new(
                ProductiveExitOutcome.Rejected,
                null,
                exception.ErrorCode,
                exception.Message);
        }
    }

    private static RegisterProductiveExitResult? Validate(
        RegisterProductiveExitCommand command)
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

    private static RegisterProductiveExitResult Invalid(
        string code,
        string message) =>
        new(ProductiveExitOutcome.InvalidRequest, null, code, message);
}
