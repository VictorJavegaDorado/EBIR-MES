using Ebir.Mes.Application.ProductionOrders;

namespace Ebir.Mes.Api.Endpoints.ProductionOrders;

public static class ProductionOrderSelectionEndpoints
{
    public static IEndpointRouteBuilder MapProductionOrderSelectionEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet("/api/production-orders", HandleAsync)
            .WithName("ListSelectableProductionOrders")
            .WithSummary("Lista órdenes MES disponibles para iniciar producción.")
            .Produces<IReadOnlyList<ProductionOrderSelectionResponse>>()
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        return endpoints;
    }

    private static async Task<IResult> HandleAsync(
        ListSelectableProductionOrders useCase,
        CancellationToken cancellationToken)
    {
        try
        {
            var orders = await useCase.ExecuteAsync(cancellationToken);
            return Results.Ok(orders.Select(order => new ProductionOrderSelectionResponse(
                order.ProductionOrderId, order.OrderNumber, order.ProductNumber,
                order.ProductDescription, order.LotNumber, order.TargetQuantity,
                order.GoodQuantity, order.ReservedQuantity, order.ScrapQuantity,
                order.RunTimeMinutes, order.State, order.ImportedAtUtc)));
        }
        catch (ProductionOrderSelectionUnavailableException)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status503ServiceUnavailable,
                title: "Consulta de órdenes no disponible",
                detail: "No se pueden consultar las órdenes en este momento.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "PRODUCTION_ORDER_SELECTION_UNAVAILABLE"
                });
        }
    }
}
