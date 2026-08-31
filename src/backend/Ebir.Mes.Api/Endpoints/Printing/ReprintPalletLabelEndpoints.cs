using Ebir.Mes.Application.Printing;

namespace Ebir.Mes.Api.Endpoints.Printing;

public static class ReprintPalletLabelEndpoints
{
    public static IEndpointRouteBuilder MapReprintPalletLabelEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost(
                "/api/pallets/{palletId:long}/label-reprints",
                HandleAsync)
            .WithName("ReprintPalletLabel")
            .WithSummary("Solicita una copia supervisada de una etiqueta de palé.")
            .Produces<ReprintPalletLabelResponse>(201)
            .ProducesProblem(400).ProducesProblem(409).ProducesProblem(503);
        return endpoints;
    }

    private static async Task<IResult> HandleAsync(
        long palletId,
        ReprintPalletLabelRequest request,
        ReprintPalletLabel useCase,
        CancellationToken cancellationToken)
    {
        try
        {
            var result = await useCase.ExecuteAsync(
                new(
                    palletId,
                    request.RequestedBySupervisorId,
                    request.Reason,
                    request.CorrelationId),
                cancellationToken);
            return result.Outcome switch
            {
                ReprintPalletLabelOutcome.Queued => Results.Created(
                    $"/api/pallets/{palletId}/label-reprints/{result.Reprint!.PrintJobId}",
                    new ReprintPalletLabelResponse(
                        result.Reprint.PrintJobId,
                        palletId,
                        request.CorrelationId)),
                ReprintPalletLabelOutcome.InvalidRequest => Problem(
                    400,
                    "Solicitud de reimpresión no válida",
                    result),
                ReprintPalletLabelOutcome.Rejected => Problem(
                    409,
                    "Reimpresión rechazada",
                    result),
                _ => throw new InvalidOperationException()
            };
        }
        catch (PalletLabelReprintUnavailableException)
        {
            return Results.Problem(
                statusCode: 503,
                title: "Reimpresión no disponible",
                detail: "No se puede solicitar la reimpresión en este momento.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "PALLET_LABEL_REPRINT_UNAVAILABLE"
                });
        }
    }

    private static IResult Problem(
        int status,
        string title,
        ReprintPalletLabelResult result) =>
        Results.Problem(
            statusCode: status,
            title: title,
            detail: result.ErrorMessage,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = result.ErrorCode
            });
}
