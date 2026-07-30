using Ebir.Mes.Application.Scrap;

namespace Ebir.Mes.Api.Endpoints.Scrap;

public static class RegisterScrapEndpoints
{
    public static IEndpointRouteBuilder MapRegisterScrapEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost(
                "/api/line-sessions/{sessionId:long}/scrap",
                HandleAsync)
            .WithName("RegisterScrap")
            .WithSummary("Registra scrap en una sesión de línea.")
            .Produces<RegisterScrapResponse>(201)
            .ProducesProblem(400).ProducesProblem(409).ProducesProblem(503);
        return endpoints;
    }

    private static async Task<IResult> HandleAsync(
        long sessionId,
        RegisterScrapRequest request,
        RegisterScrap useCase,
        CancellationToken cancellationToken)
    {
        try
        {
            var result = await useCase.ExecuteAsync(
                new(
                    sessionId,
                    request.OrderComponentId,
                    request.ScrapReasonId,
                    request.Quantity,
                    request.Description,
                    request.RegisteredByEmployeeId,
                    request.CorrelationId),
                cancellationToken);
            return result.Outcome switch
            {
                RegisterScrapOutcome.Registered => Results.Created(
                    $"/api/scrap/{result.Scrap!.ScrapId}",
                    new RegisterScrapResponse(
                        result.Scrap.ScrapId,
                        result.Scrap.NavOperationId,
                        request.CorrelationId)),
                RegisterScrapOutcome.InvalidRequest => Problem(
                    400, "Solicitud de scrap no válida", result),
                RegisterScrapOutcome.Rejected => Problem(
                    409, "Registro de scrap rechazado", result),
                _ => throw new InvalidOperationException()
            };
        }
        catch (ScrapUnavailableException)
        {
            return Results.Problem(
                statusCode: 503,
                title: "Registro de scrap no disponible",
                detail: "No se puede registrar el scrap en este momento.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "SCRAP_UNAVAILABLE"
                });
        }
    }

    private static IResult Problem(
        int status,
        string title,
        RegisterScrapResult result) =>
        Results.Problem(
            statusCode: status,
            title: title,
            detail: result.ErrorMessage,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = result.ErrorCode
            });
}
