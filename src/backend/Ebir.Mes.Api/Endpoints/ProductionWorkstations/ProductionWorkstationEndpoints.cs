using Ebir.Mes.Application.ProductionWorkstations;

namespace Ebir.Mes.Api.Endpoints.ProductionWorkstations;

public static class ProductionWorkstationEndpoints
{
    public static IEndpointRouteBuilder MapProductionWorkstationEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost(
                "/api/production-workstations/start-or-join",
                HandleStartOrJoinAsync)
            .WithName("StartOrJoinProductionTable")
            .WithSummary("Inicia la mesa con el primer operario o incorpora otro.")
            .Produces<StartOrJoinProductionTableResponse>(StatusCodes.Status200OK)
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        endpoints.MapGet(
                "/api/production-workstations/state",
                HandleStateAsync)
            .WithName("GetProductionTableState")
            .WithSummary("Devuelve el estado persistido y los tiempos de la mesa.")
            .Produces<ProductionTableStateRecord>(StatusCodes.Status200OK)
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        return endpoints;
    }

    private static async Task<IResult> HandleStartOrJoinAsync(
        StartOrJoinProductionTableRequest request,
        StartOrJoinProductionTable useCase,
        CancellationToken cancellationToken)
    {
        try
        {
            var result = await useCase.ExecuteAsync(
                new StartOrJoinProductionTableCommand(
                    request.OrderId,
                    request.LineId,
                    request.EmployeeId,
                    request.CorrelationId),
                cancellationToken);

            return result.Outcome switch
            {
                StartOrJoinProductionTableOutcome.StartedOrJoined => Results.Ok(
                    new StartOrJoinProductionTableResponse(
                        result.Start!.LineSessionId,
                        result.Start.TimeEntryId,
                        result.Start.PalletReservationId,
                        result.Start.SessionCreated,
                        request.CorrelationId)),
                StartOrJoinProductionTableOutcome.InvalidRequest => Problem(
                    StatusCodes.Status400BadRequest,
                    "Solicitud de mesa no válida",
                    result.ErrorCode,
                    result.ErrorMessage),
                StartOrJoinProductionTableOutcome.Rejected => Problem(
                    StatusCodes.Status409Conflict,
                    "Operación de mesa rechazada",
                    result.ErrorCode,
                    result.ErrorMessage),
                _ => throw new InvalidOperationException(
                    $"Resultado de mesa no soportado: {result.Outcome}.")
            };
        }
        catch (ProductionTableUnavailableException)
        {
            return Unavailable();
        }
    }

    private static async Task<IResult> HandleStateAsync(
        long orderId,
        long lineId,
        GetProductionTableState useCase,
        CancellationToken cancellationToken)
    {
        if (orderId <= 0 || lineId <= 0)
        {
            return Problem(
                StatusCodes.Status400BadRequest,
                "Consulta de mesa no válida",
                "PRODUCTION_TABLE_KEY_INVALID",
                "orderId y lineId deben ser identificadores positivos.");
        }

        try
        {
            var state = await useCase.ExecuteAsync(orderId, lineId, cancellationToken);
            return state is null
                ? Problem(
                    StatusCodes.Status404NotFound,
                    "Mesa no iniciada",
                    "PRODUCTION_TABLE_NOT_ACTIVE",
                    "No existe una mesa activa para esta orden y línea.")
                : Results.Ok(state);
        }
        catch (ProductionTableUnavailableException)
        {
            return Unavailable();
        }
    }

    private static IResult Problem(
        int statusCode,
        string title,
        string? code,
        string? detail) =>
        Results.Problem(
            statusCode: statusCode,
            title: title,
            detail: detail,
            extensions: new Dictionary<string, object?> { ["code"] = code });

    private static IResult Unavailable() =>
        Problem(
            StatusCodes.Status503ServiceUnavailable,
            "Mesa de producción no disponible",
            "PRODUCTION_TABLE_UNAVAILABLE",
            "No se puede consultar o actualizar la mesa en este momento.");
}
