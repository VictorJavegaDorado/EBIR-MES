using Ebir.Mes.Application.ProductionDashboard;

namespace Ebir.Mes.Api.Endpoints.ProductionDashboard;

public static class ProductionDashboardEndpoints
{
    public static IEndpointRouteBuilder MapProductionDashboardEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet("/api/production-dashboard", HandleAsync)
            .WithName("GetProductionDashboard")
            .WithSummary("Devuelve el estado agregado de las lineas de fabricacion, opcionalmente filtrado por jefe de linea.")
            .Produces<ProductionDashboardSnapshotRecord>(StatusCodes.Status200OK)
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        endpoints.MapGet("/api/production-dashboard/supervisors", HandleSupervisorsAsync)
            .WithName("GetProductionDashboardSupervisors")
            .WithSummary("Devuelve los jefes de linea con lineas asignadas vigentes.")
            .Produces<IReadOnlyList<ProductionDashboardSupervisorRecord>>(StatusCodes.Status200OK)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        return endpoints;
    }

    private static async Task<IResult> HandleAsync(
        string? supervisor,
        GetProductionDashboard useCase,
        CancellationToken cancellationToken)
    {
        if (supervisor is { Length: > GetProductionDashboard.MaxSupervisorCodeLength })
        {
            return Results.Problem(
                statusCode: StatusCodes.Status400BadRequest,
                title: "Filtro de panel no valido",
                detail: "El codigo del jefe de linea no es valido.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "PRODUCTION_DASHBOARD_SUPERVISOR_INVALID"
                });
        }

        try
        {
            return Results.Ok(await useCase.ExecuteAsync(supervisor, cancellationToken));
        }
        catch (ProductionDashboardUnavailableException)
        {
            return Unavailable();
        }
    }

    private static async Task<IResult> HandleSupervisorsAsync(
        GetProductionDashboard useCase,
        CancellationToken cancellationToken)
    {
        try
        {
            return Results.Ok(await useCase.ListSupervisorsAsync(cancellationToken));
        }
        catch (ProductionDashboardUnavailableException)
        {
            return Unavailable();
        }
    }

    private static IResult Unavailable() =>
        Results.Problem(
            statusCode: StatusCodes.Status503ServiceUnavailable,
            title: "Panel de fabricacion no disponible",
            detail: "No se puede consultar el estado global de fabricacion en este momento.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "PRODUCTION_DASHBOARD_UNAVAILABLE"
            });
}
