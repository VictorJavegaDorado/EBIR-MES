namespace Ebir.Mes.Application.Replenishment;

public sealed class CreateReplenishmentRequest(IReplenishmentRequestCreator creator)
{
    public async Task<CreateReplenishmentRequestResult> ExecuteAsync(
        CreateReplenishmentRequestCommand command,
        CancellationToken cancellationToken)
    {
        var invalid = Validate(command);
        if (invalid is not null)
            return invalid;

        try
        {
            var requestId = await creator.CreateAsync(command, cancellationToken);
            return new(
                CreateReplenishmentRequestOutcome.Created,
                requestId,
                null,
                null);
        }
        catch (ReplenishmentRejectedException exception)
        {
            return new(
                CreateReplenishmentRequestOutcome.Rejected,
                null,
                exception.ErrorCode,
                exception.Message);
        }
    }

    private static CreateReplenishmentRequestResult? Validate(
        CreateReplenishmentRequestCommand command)
    {
        if (command.LineSessionId <= 0)
            return Invalid("LINE_SESSION_ID_INVALID");
        if (command.OrderComponentId <= 0)
            return Invalid("ORDER_COMPONENT_ID_INVALID");
        if (command.RequestedQuantity <= 0)
            return Invalid("REQUESTED_QUANTITY_INVALID");
        if (command.RequestedByEmployeeId <= 0)
            return Invalid("REQUESTED_BY_EMPLOYEE_ID_INVALID");
        if (command.ScrapId <= 0)
            return Invalid("SCRAP_ID_INVALID");
        if (command.CorrelationId == Guid.Empty)
            return Invalid("CORRELATION_ID_INVALID");
        return null;
    }

    private static CreateReplenishmentRequestResult Invalid(string code) =>
        new(
            CreateReplenishmentRequestOutcome.InvalidRequest,
            null,
            code,
            "La solicitud de reaprovisionamiento no es válida.");
}
