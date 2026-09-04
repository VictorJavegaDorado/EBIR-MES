using Ebir.Mes.Application.ProductionDashboard;

namespace Ebir.Mes.Api.Endpoints.ProductionDashboard;

public static class ProductionDashboardEndpoints
{
    public static IEndpointRouteBuilder MapProductionDashboardEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet("/api/production-dashboard", HandleAsync)
            .WithName("GetProductionDashboard")
            .WithSummary("Devuelve el estado agregado de todas las lineas de fabricacion.")
            .Produces<ProductionDashboardSnapshotRecord>(StatusCodes.Status200OK)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        return endpoints;
    }

    private static async Task<IResult> HandleAsync(
        GetProductionDashboard useCase,
        CancellationToken cancellationToken)
    {
        try
        {
            return Results.Ok(await useCase.ExecuteAsync(cancellationToken));
        }
        catch (ProductionDashboardUnavailableException)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status503ServiceUnavailable,
                title: "Panel de fabricacion no disponible",
                detail: "No se puede consultar el estado global de fabricacion en este momento.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "PRODUCTION_DASHBOARD_UNAVAILABLE"
                });
        }
    }
}
