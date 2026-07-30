using Ebir.Mes.Application.LineSessions;

namespace Ebir.Mes.Api.Endpoints.LineSessions;

public static class CapacitySubstitutionEndpoints
{
    public static IEndpointRouteBuilder MapCapacitySubstitutionEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost(
                "/api/line-sessions/{sessionId:long}/capacity-substitutions",
                HandleAsync)
            .WithName("StartCapacitySubstitution")
            .WithSummary("Inicia una sustitución de capacidad.")
            .Produces<StartCapacitySubstitutionResponse>(StatusCodes.Status201Created)
            .ProducesProblem(400)
            .ProducesProblem(409)
            .ProducesProblem(503);
        return endpoints;
    }

    private static async Task<IResult> HandleAsync(
        long sessionId,
        StartCapacitySubstitutionRequest request,
        StartCapacitySubstitution useCase,
        CancellationToken cancellationToken)
    {
        try
        {
            var result = await useCase.ExecuteAsync(
                new(
                    sessionId,
                    request.ReplacedOperatorId,
                    request.SubstituteSupervisorId,
                    request.Reason,
                    request.CorrelationId),
                cancellationToken);
            return result.Outcome switch
            {
                StartCapacitySubstitutionOutcome.Started => Results.Created(
                    $"/api/line-sessions/{sessionId}/capacity-substitutions/{result.Substitution!.CapacitySubstitutionId}",
                    new StartCapacitySubstitutionResponse(
                        result.Substitution.CapacitySubstitutionId,
                        result.Substitution.SupervisorTimeEntryId,
                        result.Substitution.ActiveResources,
                        request.CorrelationId)),
                StartCapacitySubstitutionOutcome.InvalidRequest => Problem(
                    400, "Solicitud de sustitución no válida", result),
                StartCapacitySubstitutionOutcome.Rejected => Problem(
                    409, "Sustitución de capacidad rechazada", result),
                _ => throw new InvalidOperationException()
            };
        }
        catch (LineSessionUnavailableException)
        {
            return Results.Problem(
                statusCode: 503,
                title: "Sustitución no disponible",
                detail: "No se puede iniciar la sustitución en este momento.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "LINE_SESSION_UNAVAILABLE"
                });
        }
    }

    private static IResult Problem(
        int status,
        string title,
        StartCapacitySubstitutionResult result) =>
        Results.Problem(
            statusCode: status,
            title: title,
            detail: result.ErrorMessage,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = result.ErrorCode
            });
}
