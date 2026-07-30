using Ebir.Mes.Application.Replenishment;

namespace Ebir.Mes.Api.Endpoints.Replenishment;

public static class TransitionReplenishmentRequestEndpoints
{
    public static IEndpointRouteBuilder MapTransitionReplenishmentRequestEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost(
                "/api/replenishment-requests/{requestId:long}/transitions",
                HandleAsync)
            .WithName("TransitionReplenishmentRequest")
            .WithSummary("Transiciona una solicitud de reaprovisionamiento.")
            .Produces<TransitionReplenishmentRequestResponse>()
            .ProducesProblem(400).ProducesProblem(409).ProducesProblem(503);
        return endpoints;
    }

    private static async Task<IResult> HandleAsync(
        long requestId,
        TransitionReplenishmentRequestRequest request,
        TransitionReplenishmentRequest useCase,
        CancellationToken cancellationToken)
    {
        try
        {
            var result = await useCase.ExecuteAsync(
                new(
                    requestId,
                    request.NewState,
                    request.EmployeeId,
                    request.Comment,
                    request.CorrelationId),
                cancellationToken);
            return result.Outcome switch
            {
                TransitionReplenishmentRequestOutcome.Transitioned => Results.Ok(
                    new TransitionReplenishmentRequestResponse(
                        requestId,
                        result.State!,
                        request.CorrelationId)),
                TransitionReplenishmentRequestOutcome.InvalidRequest => Problem(
                    400, "Transición no válida", result),
                TransitionReplenishmentRequestOutcome.Rejected => Problem(
                    409, "Transición de reaprovisionamiento rechazada", result),
                _ => throw new InvalidOperationException()
            };
        }
        catch (ReplenishmentUnavailableException)
        {
            return Results.Problem(
                statusCode: 503,
                title: "Reaprovisionamiento no disponible",
                detail: "No se puede transicionar la solicitud en este momento.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "REPLENISHMENT_UNAVAILABLE"
                });
        }
    }

    private static IResult Problem(
        int status,
        string title,
        TransitionReplenishmentRequestResult result) =>
        Results.Problem(
            statusCode: status,
            title: title,
            detail: result.ErrorMessage,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = result.ErrorCode
            });
}
