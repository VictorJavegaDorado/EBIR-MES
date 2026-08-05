namespace Ebir.Mes.Application.ProductionWorkstations;

public sealed class StartOrJoinProductionTable(IProductionTableStarter starter)
{
    public async Task<StartOrJoinProductionTableResult> ExecuteAsync(
        StartOrJoinProductionTableCommand command,
        CancellationToken cancellationToken)
    {
        var validation = Validate(command);
        if (validation is not null)
        {
            return validation;
        }

        try
        {
            var start = await starter.StartOrJoinAsync(command, cancellationToken);
            return new(
                StartOrJoinProductionTableOutcome.StartedOrJoined,
                start,
                null,
                null);
        }
        catch (ProductionTableRejectedException exception)
        {
            return new(
                StartOrJoinProductionTableOutcome.Rejected,
                null,
                exception.ErrorCode,
                exception.Message);
        }
    }

    private static StartOrJoinProductionTableResult? Validate(
        StartOrJoinProductionTableCommand command)
    {
        if (command.OrderId <= 0)
        {
            return Invalid("ORDER_ID_INVALID", "orderId debe ser un identificador positivo.");
        }

        if (command.LineId <= 0)
        {
            return Invalid("LINE_ID_INVALID", "lineId debe ser un identificador positivo.");
        }

        if (command.EmployeeId <= 0)
        {
            return Invalid("EMPLOYEE_ID_INVALID", "employeeId debe ser un identificador positivo.");
        }

        return command.CorrelationId == Guid.Empty
            ? Invalid(
                "CORRELATION_ID_INVALID",
                "correlationId debe ser un UUID distinto de cero.")
            : null;
    }

    private static StartOrJoinProductionTableResult Invalid(
        string code,
        string message) =>
        new(StartOrJoinProductionTableOutcome.InvalidRequest, null, code, message);
}
