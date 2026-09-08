using Ebir.Mes.Application.LineSessions;
using Ebir.Mes.Application.Rfid;

namespace Ebir.Mes.Api.Endpoints.LineSessions;

public static class ProductiveExitEndpoints
{
    public static IEndpointRouteBuilder MapProductiveExitEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost(
                "/api/line-sessions/{sessionId:long}/exits",
                HandleAsync)
            .WithName("RegisterProductiveExit")
            .WithSummary("Registra la salida productiva de un operario.")
            .Produces<RegisterProductiveExitResponse>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        return endpoints;
    }

    private static async Task<IResult> HandleAsync(
        long sessionId,
        RegisterProductiveExitRequest request,
        AuthorizeOperatorByRfid authorizeOperator,
        RegisterProductiveExit registerProductiveExit,
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

            var command = new RegisterProductiveExitCommand(
                sessionId,
                request.EmployeeId,
                request.CorrelationId);
            var result = await registerProductiveExit.ExecuteAsync(
                command,
                cancellationToken);

            return result.Outcome switch
            {
                ProductiveExitOutcome.Registered => Results.Ok(
                    new RegisterProductiveExitResponse(
                        result.ActiveResources!.Value,
                        request.CorrelationId)),
                ProductiveExitOutcome.InvalidRequest => ToProblem(
                    StatusCodes.Status400BadRequest,
                    "Solicitud de salida productiva no válida",
                    result),
                ProductiveExitOutcome.Rejected => ToProblem(
                    StatusCodes.Status409Conflict,
                    "Salida productiva rechazada",
                    result),
                _ => throw new InvalidOperationException(
                    $"Resultado de salida no soportado: {result.Outcome}.")
            };
        }
        catch (LineSessionUnavailableException)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status503ServiceUnavailable,
                title: "Salida productiva no disponible",
                detail: "No se puede registrar la salida productiva en este momento.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "LINE_SESSION_UNAVAILABLE"
                });
        }
    }

    private static IResult ToProblem(
        int statusCode,
        string title,
        RegisterProductiveExitResult result)
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
