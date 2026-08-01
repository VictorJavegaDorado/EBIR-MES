using Ebir.Mes.Application.ProductionOrders;

namespace Ebir.Mes.Api.Endpoints.ProductionOrders;

public static class ProductionOrderPromotionEndpoints
{
    public static IEndpointRouteBuilder MapProductionOrderPromotionEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost("/api/admin/production-orders/promote", HandleAsync)
            .WithName("PromoteProductionOrder")
            .WithSummary("Promueve de forma controlada un snapshot NAV a producción.")
            .Produces<PromoteProductionOrderResponse>(200)
            .ProducesProblem(400).ProducesProblem(404).ProducesProblem(409)
            .ProducesProblem(503);
        return endpoints;
    }

    private static async Task<IResult> HandleAsync(
        PromoteProductionOrderRequest request,
        PromoteProductionOrder useCase,
        IConfiguration configuration,
        ILoggerFactory loggerFactory,
        CancellationToken cancellationToken)
    {
        if (!configuration.GetValue<bool>("Navision:ProductionOrderPromotionEnabled"))
            return Unavailable("NAV_PRODUCTION_ORDER_PROMOTION_DISABLED",
                "La promoción manual de órdenes NAV está desactivada.");
        var logger = loggerFactory.CreateLogger("ProductionOrderPromotion");
        try
        {
            var result = await useCase.ExecuteAsync(new(
                request.InboundOrderId, request.Lot, request.OperationNumber,
                request.LotProvidedBy, request.CorrelationId), cancellationToken);
            var outcome = result.Outcome switch
            {
                ProductionOrderPromotionOutcome.Created => "CREADA",
                ProductionOrderPromotionOutcome.Unchanged => "SIN_CAMBIOS",
                ProductionOrderPromotionOutcome.ReviewRequired => "REVISION",
                _ => throw new InvalidOperationException("Unknown promotion outcome.")
            };
            logger.LogInformation(
                "Production order promotion finished with outcome {Outcome}, production order {ProductionOrderId} and correlation {CorrelationId}.",
                outcome, result.ProductionOrderId, request.CorrelationId);
            return Results.Ok(new PromoteProductionOrderResponse(
                result.ProductionOrderId, outcome, request.CorrelationId));
        }
        catch (ProductionOrderPromotionRejectedException exception)
        {
            logger.LogWarning(
                "Production order promotion rejected with code {Code} and correlation {CorrelationId}.",
                exception.Code, request.CorrelationId);
            var status = exception.Code switch
            {
                "NAV_INBOUND_ORDER_INVALID" or "NAV_PROMOTION_ID_REQUIRED" or
                "NAV_PROMOTION_LOT_INVALID" or "NAV_PROMOTION_OPERATION_INVALID" or
                "NAV_PROMOTION_LOT_PROVIDER_INVALID" => StatusCodes.Status400BadRequest,
                "NAV_INBOUND_ORDER_NOT_FOUND" => StatusCodes.Status404NotFound,
                _ => StatusCodes.Status409Conflict
            };
            return Results.Problem(statusCode: status,
                title: "Promoción de orden NAV rechazada", detail: exception.Message,
                extensions: new Dictionary<string, object?> { ["code"] = exception.Code });
        }
        catch (ProductionOrderPromotionUnavailableException)
        {
            logger.LogError(
                "Production order promotion unavailable for correlation {CorrelationId}.",
                request.CorrelationId);
            return Unavailable("NAV_PRODUCTION_ORDER_PROMOTION_UNAVAILABLE",
                "No se puede promover la orden NAV en este momento.");
        }
    }

    private static IResult Unavailable(string code, string detail) =>
        Results.Problem(statusCode: StatusCodes.Status503ServiceUnavailable,
            title: "Promoción de orden NAV no disponible", detail: detail,
            extensions: new Dictionary<string, object?> { ["code"] = code });
}
