using Ebir.Mes.Application.LineSessions;

namespace Ebir.Mes.Api.Endpoints.LineSessions;

public static class FinishLineSessionEndpoints
{
    public static IEndpointRouteBuilder MapFinishLineSessionEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost(
                "/api/line-sessions/{sessionId:long}/finish-shift",
                HandleAsync)
            .WithName("FinishLineSession")
            .WithSummary("Finaliza de forma supervisada una sesión de turno.")
            .Produces<FinishLineSessionResponse>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        return endpoints;
    }

    private static async Task<IResult> HandleAsync(
        long sessionId,
        FinishLineSessionRequest request,
        FinishLineSession finishLineSession,
        CancellationToken cancellationToken)
    {
        try
        {
            var result = await finishLineSession.ExecuteAsync(
                new FinishLineSessionCommand(
                    sessionId,
                    request.SupervisorId,
                    request.CorrelationId),
                cancellationToken);
            return result.Outcome switch
            {
                FinishLineSessionOutcome.Finished => Results.Ok(
                    new FinishLineSessionResponse(
                        result.ClosedTimeEntries!.Value,
                        request.CorrelationId)),
                FinishLineSessionOutcome.InvalidRequest => Problem(
                    400, "Solicitud de fin de turno no válida", result),
                FinishLineSessionOutcome.Rejected => Problem(
                    409, "Fin de turno rechazado", result),
                _ => throw new InvalidOperationException(
                    $"Resultado de fin de turno no soportado: {result.Outcome}.")
            };
        }
        catch (LineSessionUnavailableException)
        {
            return Results.Problem(
                statusCode: 503,
                title: "Fin de turno no disponible",
                detail: "No se puede finalizar la sesión en este momento.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "LINE_SESSION_UNAVAILABLE"
                });
        }
    }

    private static IResult Problem(
        int status,
        string title,
        FinishLineSessionResult result) =>
        Results.Problem(
            statusCode: status,
            title: title,
            detail: result.ErrorMessage,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = result.ErrorCode
            });
}
