using Ebir.Mes.Application.LineSessions;

namespace Ebir.Mes.Api.Endpoints.LineSessions;

public static class ShiftChangePendingEndpoints
{
    public static IEndpointRouteBuilder MapShiftChangePendingEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost(
                "/api/line-sessions/{sessionId:long}/shift-change-pending",
                HandleAsync)
            .WithName("MarkShiftChangePending")
            .WithSummary("Marca de forma idempotente el cambio de turno pendiente.")
            .Produces<MarkShiftChangePendingResponse>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        return endpoints;
    }

    private static async Task<IResult> HandleAsync(
        long sessionId,
        MarkShiftChangePendingRequest request,
        MarkShiftChangePending markShiftChangePending,
        CancellationToken cancellationToken)
    {
        try
        {
            var result = await markShiftChangePending.ExecuteAsync(
                new MarkShiftChangePendingCommand(
                    sessionId,
                    request.CorrelationId),
                cancellationToken);

            return result.Outcome switch
            {
                ShiftChangePendingOutcome.Processed => Results.Ok(
                    new MarkShiftChangePendingResponse(
                        result.ChangeMarked!.Value,
                        request.CorrelationId)),
                ShiftChangePendingOutcome.InvalidRequest => ToProblem(
                    StatusCodes.Status400BadRequest,
                    "Solicitud de cambio de turno no válida",
                    result),
                ShiftChangePendingOutcome.Rejected => ToProblem(
                    StatusCodes.Status409Conflict,
                    "Cambio de turno rechazado",
                    result),
                _ => throw new InvalidOperationException(
                    $"Resultado de cambio de turno no soportado: {result.Outcome}.")
            };
        }
        catch (LineSessionUnavailableException)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status503ServiceUnavailable,
                title: "Cambio de turno no disponible",
                detail: "No se puede marcar el cambio de turno en este momento.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "LINE_SESSION_UNAVAILABLE"
                });
        }
    }

    private static IResult ToProblem(
        int statusCode,
        string title,
        MarkShiftChangePendingResult result) =>
        Results.Problem(
            statusCode: statusCode,
            title: title,
            detail: result.ErrorMessage,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = result.ErrorCode
            });
}
