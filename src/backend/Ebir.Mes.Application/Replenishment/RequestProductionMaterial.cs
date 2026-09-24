namespace Ebir.Mes.Application.Replenishment;

public sealed record MaterialRequestOption(
    long OrderComponentId,
    string OrderNumber,
    string ComponentCode,
    string Description,
    string? UnitOfMeasure,
    decimal? TheoreticalQuantity,
    int OpenRequestCount);

public interface IMaterialRequestOptionsReader
{
    Task<IReadOnlyList<MaterialRequestOption>> ReadAsync(
        long lineSessionId,
        CancellationToken cancellationToken);
}

public interface INavisionMaterialRequester
{
    Task<int> RequestAsync(
        string orderNumber,
        string componentCode,
        int quantity,
        Guid correlationId,
        CancellationToken cancellationToken);
}

public sealed record RequestProductionMaterialCommand(
    long LineSessionId,
    long OrderComponentId,
    int Quantity,
    long EmployeeId,
    Guid CorrelationId);

public sealed record RequestProductionMaterialResult(
    bool Succeeded,
    long? LocalRequestId,
    int? NavRequestId,
    string? ErrorCode,
    string? ErrorMessage);

public sealed class RequestProductionMaterial(
    IMaterialRequestOptionsReader optionsReader,
    IReplenishmentRequestCreator creator,
    INavisionMaterialRequester navision)
{
    public async Task<RequestProductionMaterialResult> ExecuteAsync(
        RequestProductionMaterialCommand command,
        CancellationToken cancellationToken)
    {
        if (command.LineSessionId <= 0 || command.OrderComponentId <= 0
            || command.Quantity <= 0 || command.EmployeeId <= 0
            || command.CorrelationId == Guid.Empty)
            return Failure("MATERIAL_REQUEST_INVALID", "La solicitud de material no es válida.");

        var options = await optionsReader.ReadAsync(command.LineSessionId, cancellationToken);
        var selected = options.SingleOrDefault(x => x.OrderComponentId == command.OrderComponentId);
        if (selected is null)
            return Failure("ORDER_COMPONENT_NOT_FOUND", "El componente no pertenece a la orden activa.");

        long localId;
        try
        {
            localId = await creator.CreateAsync(
                new(command.LineSessionId, command.OrderComponentId, command.Quantity,
                    command.EmployeeId, null, command.CorrelationId),
                cancellationToken);
        }
        catch (ReplenishmentRejectedException exception)
        {
            return Failure(exception.ErrorCode, exception.Message);
        }
        catch (ReplenishmentUnavailableException exception)
        {
            throw new MaterialRequestUnavailableException(
                "No se puede registrar la solicitud local.", exception);
        }

        var navId = await navision.RequestAsync(
            selected.OrderNumber, selected.ComponentCode, command.Quantity,
            command.CorrelationId, cancellationToken);
        return new(true, localId, navId, null, null);
    }

    private static RequestProductionMaterialResult Failure(string code, string message) =>
        new(false, null, null, code, message);
}

public sealed class MaterialRequestUnavailableException(string message, Exception? inner = null)
    : Exception(message, inner);
