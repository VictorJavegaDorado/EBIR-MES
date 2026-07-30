using Ebir.Mes.Application.Replenishment;

namespace Ebir.Mes.Api.Endpoints.Replenishment;

public static class CreateReplenishmentRequestEndpoints
{
    public static IEndpointRouteBuilder MapCreateReplenishmentRequestEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost(
                "/api/line-sessions/{sessionId:long}/replenishment-requests",
                HandleAsync)
            .WithName("CreateReplenishmentRequest")
            .WithSummary("Crea una solicitud de reaprovisionamiento.")
            .Produces<CreateReplenishmentRequestResponse>(201)
            .ProducesProblem(400).ProducesProblem(409).ProducesProblem(503);
        return endpoints;
    }

    private static async Task<IResult> HandleAsync(
        long sessionId,
        CreateReplenishmentRequestRequest request,
        CreateReplenishmentRequest useCase,
        CancellationToken cancellationToken)
    {
        try
        {
            var result = await useCase.ExecuteAsync(
                new(
                    sessionId,
                    request.OrderComponentId,
                    request.RequestedQuantity,
                    request.RequestedByEmployeeId,
                    request.ScrapId,
                    request.CorrelationId),
                cancellationToken);
            return result.Outcome switch
            {
                CreateReplenishmentRequestOutcome.Created => Results.Created(
                    $"/api/replenishment-requests/{result.RequestId}",
                    new CreateReplenishmentRequestResponse(
                        result.RequestId!.Value,
                        "PENDIENTE",
                        request.ScrapId,
                        request.CorrelationId)),
                CreateReplenishmentRequestOutcome.InvalidRequest => Problem(
                    400, "Solicitud de reaprovisionamiento no válida", result),
                CreateReplenishmentRequestOutcome.Rejected => Problem(
                    409, "Solicitud de reaprovisionamiento rechazada", result),
                _ => throw new InvalidOperationException()
            };
        }
        catch (ReplenishmentUnavailableException)
        {
            return Results.Problem(
                statusCode: 503,
                title: "Reaprovisionamiento no disponible",
                detail: "No se puede crear la solicitud en este momento.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "REPLENISHMENT_UNAVAILABLE"
                });
        }
    }

    private static IResult Problem(
        int status,
        string title,
        CreateReplenishmentRequestResult result) =>
        Results.Problem(
            statusCode: status,
            title: title,
            detail: result.ErrorMessage,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = result.ErrorCode
            });
}
