using Ebir.Mes.Application.LineSessions;

namespace Ebir.Mes.Api.Endpoints.LineSessions;

public static class FinishOperatorStopEndpoints
{
    public static IEndpointRouteBuilder MapFinishOperatorStopEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost(
                "/api/line-sessions/{sessionId:long}/operator-stops/finish",
                HandleAsync)
            .WithName("FinishOperatorStop")
            .WithSummary("Finaliza el paro abierto de un operario.")
            .Produces<FinishOperatorStopResponse>()
            .ProducesProblem(400).ProducesProblem(409).ProducesProblem(503);
        return endpoints;
    }

    private static async Task<IResult> HandleAsync(
        long sessionId, FinishOperatorStopRequest request,
        FinishOperatorStop useCase, CancellationToken cancellationToken)
    {
        try
        {
            var result = await useCase.ExecuteAsync(
                new(sessionId, request.EmployeeId, request.CorrelationId),
                cancellationToken);
            return result.Outcome switch
            {
                FinishOperatorStopOutcome.Finished => Results.Ok(
                    new FinishOperatorStopResponse(
                        result.Stop!.OperatorStopId,
                        result.Stop.FinishedSubstitutionId,
                        result.Stop.ActiveResources,
                        request.CorrelationId)),
                FinishOperatorStopOutcome.InvalidRequest => Problem(400,
                    "Solicitud de retorno no válida", result),
                FinishOperatorStopOutcome.Rejected => Problem(409,
                    "Retorno de paro rechazado", result),
                _ => throw new InvalidOperationException()
            };
        }
        catch (LineSessionUnavailableException)
        {
            return Results.Problem(statusCode: 503,
                title: "Retorno de paro no disponible",
                detail: "No se puede finalizar el paro en este momento.",
                extensions: new Dictionary<string, object?>
                { ["code"] = "LINE_SESSION_UNAVAILABLE" });
        }
    }

    private static IResult Problem(
        int status, string title, FinishOperatorStopResult result) =>
        Results.Problem(statusCode: status, title: title,
            detail: result.ErrorMessage,
            extensions: new Dictionary<string, object?> { ["code"] = result.ErrorCode });
}
