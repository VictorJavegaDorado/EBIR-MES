namespace Ebir.Mes.Application.ProductionWorkstations;

public sealed class CompleteProductionOrder(IProductionOrderCompleter completer)
{
    public async Task<CompleteProductionOrderResult> ExecuteAsync(
        CompleteProductionOrderCommand command,
        CancellationToken cancellationToken)
    {
        if (command.LineSessionId <= 0)
        {
            return Invalid(
                "LINE_SESSION_ID_INVALID",
                "lineSessionId debe ser un identificador positivo.");
        }

        if (command.CorrelationId == Guid.Empty)
        {
            return Invalid(
                "CORRELATION_ID_INVALID",
                "correlationId debe ser un UUID distinto de cero.");
        }

        try
        {
            await completer.CompleteAsync(command, cancellationToken);
            return new(CompleteProductionOrderOutcome.Completed, null, null);
        }
        catch (ProductionTableRejectedException exception)
        {
            return new(
                CompleteProductionOrderOutcome.Rejected,
                exception.ErrorCode,
                exception.Message);
        }
    }

    private static CompleteProductionOrderResult Invalid(
        string code,
        string message) =>
        new(CompleteProductionOrderOutcome.InvalidRequest, code, message);
}
