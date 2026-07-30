namespace Ebir.Mes.Application.Scrap;

public sealed class RegisterScrap(IScrapRegistrar registrar)
{
    public const int MaximumDescriptionLength = 1000;

    public async Task<RegisterScrapResult> ExecuteAsync(
        RegisterScrapCommand command,
        CancellationToken cancellationToken)
    {
        var description = string.IsNullOrWhiteSpace(command.Description)
            ? null
            : command.Description.Trim();
        var normalized = command with { Description = description };
        var invalid = Validate(normalized);
        if (invalid is not null)
            return invalid;

        try
        {
            var scrap = await registrar.RegisterAsync(normalized, cancellationToken);
            return new(RegisterScrapOutcome.Registered, scrap, null, null);
        }
        catch (ScrapRejectedException exception)
        {
            return new(
                RegisterScrapOutcome.Rejected,
                null,
                exception.ErrorCode,
                exception.Message);
        }
    }

    private static RegisterScrapResult? Validate(RegisterScrapCommand command)
    {
        if (command.LineSessionId <= 0)
            return Invalid("LINE_SESSION_ID_INVALID");
        if (command.OrderComponentId <= 0)
            return Invalid("ORDER_COMPONENT_ID_INVALID");
        if (command.ScrapReasonId <= 0)
            return Invalid("SCRAP_REASON_ID_INVALID");
        if (command.Quantity <= 0)
            return Invalid("SCRAP_QUANTITY_INVALID");
        if (command.Description?.Length > MaximumDescriptionLength)
            return Invalid("SCRAP_DESCRIPTION_TOO_LONG");
        if (command.RegisteredByEmployeeId <= 0)
            return Invalid("REGISTERED_BY_EMPLOYEE_ID_INVALID");
        if (command.CorrelationId == Guid.Empty)
            return Invalid("CORRELATION_ID_INVALID");
        return null;
    }

    private static RegisterScrapResult Invalid(string code) =>
        new(
            RegisterScrapOutcome.InvalidRequest,
            null,
            code,
            "La solicitud de registro de scrap no es válida.");
}
