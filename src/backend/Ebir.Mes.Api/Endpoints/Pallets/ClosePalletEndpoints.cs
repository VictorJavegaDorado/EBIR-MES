using Ebir.Mes.Application.Pallets.ClosePallet;

namespace Ebir.Mes.Api.Endpoints.Pallets;

public static class ClosePalletEndpoints
{
    public static IEndpointRouteBuilder MapClosePalletEndpoints(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost("/api/pallet-reservations/{reservationId:long}/close", HandleAsync)
            .WithName("ClosePallet")
            .WithSummary("Cierra manualmente un palé de forma idempotente.")
            .Produces<ClosePalletResponse>(200)
            .ProducesProblem(400).ProducesProblem(409).ProducesProblem(503);
        return endpoints;
    }

    private static async Task<IResult> HandleAsync(long reservationId, ClosePalletRequest request, ClosePallet useCase, CancellationToken cancellationToken)
    {
        try
        {
            var result = await useCase.ExecuteAsync(new(reservationId, request.GoodQuantity, request.ClosedByEmployeeId, request.AuthorizingSupervisorId, request.IsPartial, request.PartialReason, request.CorrelationId), cancellationToken);
            return result.Outcome switch
            {
                ClosePalletOutcome.Closed => Results.Ok(new ClosePalletResponse(result.Pallet!.PalletId, request.CorrelationId)),
                ClosePalletOutcome.InvalidRequest => Problem(400, "Solicitud de cierre de palé no válida", result),
                ClosePalletOutcome.Rejected => Problem(409, "Cierre de palé rechazado", result),
                _ => throw new InvalidOperationException()
            };
        }
        catch (PalletCloseUnavailableException)
        {
            return Results.Problem(statusCode: 503, title: "Cierre de palé no disponible", detail: "No se puede cerrar el palé en este momento.", extensions: new Dictionary<string, object?> { ["code"] = "PALLET_CLOSE_UNAVAILABLE" });
        }
    }

    private static IResult Problem(int status, string title, ClosePalletResult result) =>
        Results.Problem(statusCode: status, title: title, detail: result.ErrorMessage, extensions: new Dictionary<string, object?> { ["code"] = result.ErrorCode });
}
