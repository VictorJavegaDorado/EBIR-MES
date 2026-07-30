using Ebir.Mes.Application.LineSessions;

namespace Ebir.Mes.Api.Endpoints.LineSessions;

public static class LineSessionEndpoints
{
    public static IEndpointRouteBuilder MapLineSessionEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost("/api/line-sessions", HandleAsync)
            .WithName("OpenLineSession")
            .WithSummary("Abre una sesión de línea.")
            .Produces<OpenLineSessionResponse>(StatusCodes.Status201Created)
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        return endpoints;
    }

    private static async Task<IResult> HandleAsync(
        OpenLineSessionRequest request,
        OpenLineSession openLineSession,
        CancellationToken cancellationToken)
    {
        try
        {
            var command = new OpenLineSessionCommand(
                request.OrderId, request.LineId, request.PalletFormatOrderId,
                request.SupervisorId, request.OutsideScheduleConfirmed,
                request.CorrelationId);
            var result = await openLineSession.ExecuteAsync(command, cancellationToken);

            return result.Outcome switch
            {
                OpenLineSessionOutcome.Opened => Results.Created(
                    $"/api/line-sessions/{result.LineSessionId}",
                    new OpenLineSessionResponse(
                        result.LineSessionId!.Value,
                        request.CorrelationId)),
                OpenLineSessionOutcome.InvalidRequest => ToProblem(
                    StatusCodes.Status400BadRequest,
                    "Solicitud de apertura no válida",
                    result),
                OpenLineSessionOutcome.Rejected => ToProblem(
                    StatusCodes.Status409Conflict,
                    "Apertura de sesión rechazada",
                    result),
                _ => throw new InvalidOperationException(
                    $"Resultado de apertura no soportado: {result.Outcome}.")
            };
        }
        catch (LineSessionUnavailableException)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status503ServiceUnavailable,
                title: "Apertura de sesión no disponible",
                detail: "No se puede abrir la sesión de línea en este momento.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "LINE_SESSION_UNAVAILABLE"
                });
        }
    }

    private static IResult ToProblem(
        int statusCode,
        string title,
        OpenLineSessionResult result)
    {
        return Results.Problem(
            statusCode: statusCode,
            title: title,
            detail: result.ErrorMessage,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = result.ErrorCode
            });
    }
}
