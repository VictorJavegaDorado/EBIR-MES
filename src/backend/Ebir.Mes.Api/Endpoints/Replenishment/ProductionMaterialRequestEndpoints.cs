using Ebir.Mes.Application.Replenishment;

namespace Ebir.Mes.Api.Endpoints.Replenishment;

public static class ProductionMaterialRequestEndpoints
{
    public static IEndpointRouteBuilder MapProductionMaterialRequestEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet("/api/line-sessions/{sessionId:long}/material-request-options",
            GetOptionsAsync).Produces<IReadOnlyList<MaterialRequestOption>>();
        endpoints.MapPost("/api/line-sessions/{sessionId:long}/material-requests",
            RequestAsync).Produces<MaterialRequestResponse>(201)
            .ProducesProblem(400).ProducesProblem(409).ProducesProblem(503);
        endpoints.MapGet("/api/line-sessions/{sessionId:long}/material-request-statuses",
            GetStatusesAsync).Produces<IReadOnlyList<ProductionMaterialRequestStatus>>()
            .ProducesProblem(503);
        return endpoints;
    }

    private static async Task<IResult> GetOptionsAsync(long sessionId,
        IMaterialRequestOptionsReader reader, CancellationToken cancellationToken)
    {
        try { return Results.Ok(await reader.ReadAsync(sessionId, cancellationToken)); }
        catch (MaterialRequestUnavailableException)
        { return Unavailable(); }
    }

    private static async Task<IResult> RequestAsync(long sessionId,
        MaterialRequestBody body, RequestProductionMaterial useCase,
        IConfiguration configuration,
        CancellationToken cancellationToken)
    {
        if (!configuration.GetValue<bool>("Navision:MaterialRequestEnabled"))
            return Results.Problem(statusCode: 503,
                title: "Solicitud de material no disponible",
                detail: "El envío de solicitudes a NAV está desactivado.",
                extensions: new Dictionary<string, object?>
                { ["code"] = "MATERIAL_REQUEST_DISABLED" });
        try
        {
            var result = await useCase.ExecuteAsync(new(sessionId, body.OrderComponentId,
                body.Quantity, body.EmployeeId, body.CorrelationId), cancellationToken);
            return result.Succeeded
                ? Results.Created($"/api/replenishment-requests/{result.LocalRequestId}",
                    new MaterialRequestResponse(result.LocalRequestId!.Value,
                        result.NavRequestId!.Value, "PENDIENTE_CREAR", body.CorrelationId))
                : Results.Problem(statusCode: result.ErrorCode == "MATERIAL_REQUEST_INVALID" ? 400 : 409,
                    title: "Solicitud de material rechazada", detail: result.ErrorMessage,
                    extensions: new Dictionary<string, object?> { ["code"] = result.ErrorCode });
        }
        catch (MaterialRequestUnavailableException) { return Unavailable(); }
    }

    private static async Task<IResult> GetStatusesAsync(
        long sessionId,
        GetProductionMaterialRequestStatuses useCase,
        IConfiguration configuration,
        CancellationToken cancellationToken)
    {
        if (!configuration.GetValue<bool>("Navision:MaterialRequestEnabled"))
            return Results.Problem(statusCode: 503,
                title: "Seguimiento de material no disponible",
                detail: "El seguimiento de solicitudes NAV está desactivado.",
                extensions: new Dictionary<string, object?>
                { ["code"] = "MATERIAL_REQUEST_DISABLED" });
        try { return Results.Ok(await useCase.ExecuteAsync(sessionId, cancellationToken)); }
        catch (MaterialRequestUnavailableException) { return Unavailable(); }
    }

    private static IResult Unavailable() => Results.Problem(statusCode: 503,
        title: "Solicitud de material no disponible",
        detail: "No se puede enviar la solicitud en este momento.",
        extensions: new Dictionary<string, object?> { ["code"] = "MATERIAL_REQUEST_UNAVAILABLE" });
}

public sealed record MaterialRequestBody(long OrderComponentId, int Quantity,
    long EmployeeId, Guid CorrelationId);
public sealed record MaterialRequestResponse(long Id, int NavRequestId, string State,
    Guid CorrelationId);
