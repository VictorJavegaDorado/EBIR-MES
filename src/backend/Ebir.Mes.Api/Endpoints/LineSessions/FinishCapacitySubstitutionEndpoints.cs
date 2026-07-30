using Ebir.Mes.Application.LineSessions;

namespace Ebir.Mes.Api.Endpoints.LineSessions;

public static class FinishCapacitySubstitutionEndpoints
{
    public static IEndpointRouteBuilder MapFinishCapacitySubstitutionEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost(
                "/api/capacity-substitutions/{substitutionId:long}/finish",
                HandleAsync)
            .WithName("FinishCapacitySubstitution")
            .WithSummary("Finaliza una sustitución de capacidad.")
            .Produces<FinishCapacitySubstitutionResponse>()
            .ProducesProblem(400).ProducesProblem(409).ProducesProblem(503);
        return endpoints;
    }

    private static async Task<IResult> HandleAsync(
        long substitutionId,
        FinishCapacitySubstitutionRequest request,
        FinishCapacitySubstitution useCase,
        CancellationToken cancellationToken)
    {
        try
        {
            var result = await useCase.ExecuteAsync(
                new(
                    substitutionId,
                    request.SupervisorId,
                    request.Reason,
                    request.CorrelationId),
                cancellationToken);
            return result.Outcome switch
            {
                FinishCapacitySubstitutionOutcome.Finished => Results.Ok(
                    new FinishCapacitySubstitutionResponse(
                        substitutionId,
                        result.ActiveResources!.Value,
                        request.CorrelationId)),
                FinishCapacitySubstitutionOutcome.InvalidRequest => Problem(
                    400, "Solicitud de finalización no válida", result),
                FinishCapacitySubstitutionOutcome.Rejected => Problem(
                    409, "Finalización de sustitución rechazada", result),
                _ => throw new InvalidOperationException()
            };
        }
        catch (LineSessionUnavailableException)
        {
            return Results.Problem(
                statusCode: 503,
                title: "Finalización no disponible",
                detail: "No se puede finalizar la sustitución en este momento.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "LINE_SESSION_UNAVAILABLE"
                });
        }
    }

    private static IResult Problem(
        int status,
        string title,
        FinishCapacitySubstitutionResult result) =>
        Results.Problem(
            statusCode: status,
            title: title,
            detail: result.ErrorMessage,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = result.ErrorCode
            });
}
