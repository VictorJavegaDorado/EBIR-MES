using Ebir.Mes.Application.Scrap;

namespace Ebir.Mes.Api.Endpoints.Scrap;

public static class ReviewScrapEndpoints
{
    public static IEndpointRouteBuilder MapReviewScrapEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost("/api/scrap/{scrapId:long}/revisions", HandleAsync)
            .WithName("ReviewScrap")
            .WithSummary("Corrige o anula un registro de scrap.")
            .Produces<ReviewScrapResponse>(201)
            .ProducesProblem(400).ProducesProblem(409).ProducesProblem(503);
        return endpoints;
    }

    private static async Task<IResult> HandleAsync(
        long scrapId,
        ReviewScrapRequest request,
        ReviewScrap useCase,
        CancellationToken cancellationToken)
    {
        try
        {
            var result = await useCase.ExecuteAsync(
                new(
                    scrapId,
                    request.OrderComponentId,
                    request.ScrapReasonId,
                    request.Quantity,
                    request.Description,
                    request.IsCancellation,
                    request.AdjustedBySupervisorId,
                    request.AdjustmentReason,
                    request.CorrelationId),
                cancellationToken);
            return result.Outcome switch
            {
                ReviewScrapOutcome.Reviewed => Results.Created(
                    $"/api/scrap/{scrapId}/revisions/{result.Revision!.ScrapRevisionId}",
                    new ReviewScrapResponse(
                        result.Revision.ScrapRevisionId,
                        scrapId,
                        result.Revision.NavOperationId,
                        request.IsCancellation,
                        request.CorrelationId)),
                ReviewScrapOutcome.InvalidRequest => Problem(
                    400, "Solicitud de revisión no válida", result),
                ReviewScrapOutcome.Rejected => Problem(
                    409, "Revisión de scrap rechazada", result),
                _ => throw new InvalidOperationException()
            };
        }
        catch (ScrapUnavailableException)
        {
            return Results.Problem(
                statusCode: 503,
                title: "Revisión de scrap no disponible",
                detail: "No se puede revisar el scrap en este momento.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "SCRAP_UNAVAILABLE"
                });
        }
    }

    private static IResult Problem(
        int status,
        string title,
        ReviewScrapResult result) =>
        Results.Problem(
            statusCode: status,
            title: title,
            detail: result.ErrorMessage,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = result.ErrorCode
            });
}
