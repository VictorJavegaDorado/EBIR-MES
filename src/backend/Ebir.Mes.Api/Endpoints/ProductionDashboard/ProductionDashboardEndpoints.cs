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

        endpoints.MapGet("/api/production-dashboard/line-assignments", HandleLineAssignmentsAsync)
            .WithName("GetProductionDashboardLineAssignments")
            .WithSummary("Devuelve todas las lineas activas con su jefe vigente, si lo tienen.")
            .Produces<IReadOnlyList<LineAssignmentOptionRecord>>(StatusCodes.Status200OK)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        endpoints.MapPost("/api/production-dashboard/line-assignments", HandleSetLineAssignmentsAsync)
            .WithName("SetProductionDashboardLineAssignments")
            .WithSummary("Guarda las lineas que un jefe de linea quiere ver en su propio panel.")
            .Produces<IReadOnlyList<LineAssignmentOptionRecord>>(StatusCodes.Status200OK)
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status409Conflict)
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

    private static async Task<IResult> HandleLineAssignmentsAsync(
        GetProductionDashboard useCase,
        CancellationToken cancellationToken)
    {
        try
        {
            return Results.Ok(await useCase.ListLineAssignmentOptionsAsync(cancellationToken));
        }
        catch (ProductionDashboardUnavailableException)
        {
            return Unavailable();
        }
    }

    private static async Task<IResult> HandleSetLineAssignmentsAsync(
        SetLineAssignmentsRequest request,
        SetSupervisorLineAssignments useCase,
        CancellationToken cancellationToken)
    {
        try
        {
            var lines = await useCase.ExecuteAsync(
                request.EmployeeId,
                request.LineIds ?? Array.Empty<long>(),
                cancellationToken);
            return Results.Ok(lines);
        }
        catch (ArgumentOutOfRangeException)
        {
            return Problem(StatusCodes.Status400BadRequest, "LINE_ASSIGNMENT_REQUEST_INVALID");
        }
        catch (LineSupervisorAssignmentRejectedException ex)
        {
            var status = ex.Code switch
            {
                "EMPLOYEE_NOT_ACTIVE_SUPERVISOR" => StatusCodes.Status403Forbidden,
                "LINE_ASSIGNMENT_LOCKED" => StatusCodes.Status409Conflict,
                _ => StatusCodes.Status400BadRequest
            };
            return Problem(status, ex.Code);
        }
        catch (ProductionDashboardUnavailableException)
        {
            return Unavailable();
        }
    }

    private static IResult Problem(int statusCode, string code) =>
        Results.Problem(
            statusCode: statusCode,
            title: "Seleccion de mesas no completada",
            extensions: new Dictionary<string, object?> { ["code"] = code });

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

public sealed record SetLineAssignmentsRequest(long EmployeeId, IReadOnlyList<long>? LineIds);
