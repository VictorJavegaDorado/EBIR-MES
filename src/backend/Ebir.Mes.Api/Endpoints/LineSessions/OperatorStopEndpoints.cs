using Ebir.Mes.Application.LineSessions;
using Ebir.Mes.Application.Rfid;

namespace Ebir.Mes.Api.Endpoints.LineSessions;

public static class OperatorStopEndpoints
{
    public static IEndpointRouteBuilder MapOperatorStopEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost(
                "/api/line-sessions/{sessionId:long}/operator-stops",
                HandleAsync)
            .WithName("StartOperatorStop")
            .WithSummary("Inicia un paro individual de operario.")
            .Produces<StartOperatorStopResponse>(StatusCodes.Status201Created)
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        return endpoints;
    }

    private static async Task<IResult> HandleAsync(
        long sessionId,
        StartOperatorStopRequest request,
        AuthorizeOperatorByRfid authorizeOperator,
        StartOperatorStop startOperatorStop,
        CancellationToken cancellationToken)
    {
        try
        {
            var authorization = await authorizeOperator.ExecuteAsync(
                request.EmployeeId,
                request.Credential,
                cancellationToken);
            if (!authorization.Authorized)
            {
                return Results.Problem(
                    statusCode: authorization.ErrorCode == "EMPLOYEE_ID_INVALID"
                        ? StatusCodes.Status400BadRequest
                        : StatusCodes.Status403Forbidden,
                    title: "RFID no autorizado",
                    detail: authorization.ErrorMessage,
                    extensions: new Dictionary<string, object?>
                    {
                        ["code"] = authorization.ErrorCode
                    });
            }

            var result = await startOperatorStop.ExecuteAsync(
                new(sessionId, request.EmployeeId, request.Reason, request.CorrelationId),
                cancellationToken);
            return result.Outcome switch
            {
                StartOperatorStopOutcome.Started => Results.Created(
                    $"/api/line-sessions/{sessionId}/operator-stops/{result.Stop!.OperatorStopId}",
                    new StartOperatorStopResponse(
                        result.Stop.OperatorStopId,
                        result.Stop.ActiveResources,
                        request.CorrelationId)),
                StartOperatorStopOutcome.InvalidRequest => Problem(
                    400, "Solicitud de paro no válida", result),
                StartOperatorStopOutcome.Rejected => Problem(
                    409, "Inicio de paro rechazado", result),
                _ => throw new InvalidOperationException(
                    $"Resultado de paro no soportado: {result.Outcome}.")
            };
        }
        catch (LineSessionUnavailableException)
        {
            return Results.Problem(
                statusCode: 503,
                title: "Inicio de paro no disponible",
                detail: "No se puede iniciar el paro en este momento.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "LINE_SESSION_UNAVAILABLE"
                });
        }
    }

    private static IResult Problem(
        int status,
        string title,
        StartOperatorStopResult result) =>
        Results.Problem(
            statusCode: status,
            title: title,
            detail: result.ErrorMessage,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = result.ErrorCode
            });
}
