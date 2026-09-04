using Ebir.Mes.Application.ProductionOrders;

namespace Ebir.Mes.Api.Endpoints.ProductionOrders;

public static class ProductionOrderPreparationEndpoints
{
    public static IEndpointRouteBuilder MapProductionOrderPreparationEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost("/api/production-orders/prepare", HandleAsync)
            .WithName("PrepareProductionOrder")
            .WithSummary(
                "Prepara una orden lanzada exacta de EbirTest para su selección en MES.")
            .Produces<ProductionOrderSelectionResponse>(200)
            .ProducesProblem(400)
            .ProducesProblem(404)
            .ProducesProblem(409)
            .ProducesProblem(503);
        return endpoints;
    }

    private static async Task<IResult> HandleAsync(
        PrepareProductionOrderRequest request,
        IServiceProvider services,
        IConfiguration applicationConfiguration,
        ILoggerFactory loggerFactory,
        CancellationToken cancellationToken)
    {
        var configuration = ProductionOrderSynchronizationConfiguration.Read(
            applicationConfiguration);
        if (!configuration.PreparationEnabled)
        {
            return Unavailable(
                "NAV_PRODUCTION_ORDER_PREPARATION_DISABLED",
                "La preparación automática de órdenes NAV está desactivada.");
        }

        var logger = loggerFactory.CreateLogger("ProductionOrderPreparation");
        logger.LogInformation(
            "Production order preparation requested for order {OrderNumber} with correlation {CorrelationId}.",
            request.OrderNumber,
            request.CorrelationId);

        try
        {
            configuration.CreateNavisionOptions();
            var useCase = services.GetRequiredService<PrepareProductionOrder>();
            var result = await useCase.ExecuteAsync(
                new PrepareProductionOrderCommand(
                    configuration.EnvironmentCode,
                    configuration.CompanyCode,
                    request.OrderNumber,
                    request.CorrelationId),
                cancellationToken);
            logger.LogInformation(
                "Production order preparation finished for production order {ProductionOrderId} with correlation {CorrelationId}.",
                result.Order.ProductionOrderId,
                request.CorrelationId);
            return Results.Ok(ToResponse(result.Order));
        }
        catch (ProductionOrderSynchronizationRejectedException exception)
        {
            logger.LogWarning(
                "Production order preparation rejected during synchronization with code {Code} and correlation {CorrelationId}.",
                exception.Code,
                request.CorrelationId);
            return SynchronizationRejected(exception);
        }
        catch (ProductionOrderPromotionRejectedException exception)
        {
            logger.LogWarning(
                "Production order preparation rejected during promotion with code {Code} and correlation {CorrelationId}.",
                exception.Code,
                request.CorrelationId);
            return Rejected(StatusCodes.Status409Conflict, exception.Code, exception.Message);
        }
        catch (ProductionOrderPreparationRejectedException exception)
        {
            logger.LogWarning(
                "Production order preparation rejected with code {Code} and correlation {CorrelationId}.",
                exception.Code,
                request.CorrelationId);
            return Rejected(StatusCodes.Status409Conflict, exception.Code, exception.Message);
        }
        catch (Exception exception)
            when (exception is ProductionOrderSourceUnavailableException or
                  ProductionOrderSynchronizationUnavailableException or
                  ProductionOrderPromotionUnavailableException or
                  ProductionOrderSelectionUnavailableException)
        {
            logger.LogError(
                exception,
                "Production order preparation unavailable for correlation {CorrelationId}.",
                request.CorrelationId);
            return Unavailable(
                "NAV_PRODUCTION_ORDER_PREPARATION_UNAVAILABLE",
                "No se puede preparar la orden NAV en este momento.");
        }
    }

    private static IResult SynchronizationRejected(
        ProductionOrderSynchronizationRejectedException exception)
    {
        var statusCode = exception.Code switch
        {
            "NAV_ENVIRONMENT_INVALID" or
            "NAV_COMPANY_INVALID" or
            "NAV_ORDER_NUMBER_INVALID" or
            "NAV_SYNCHRONIZATION_ID_REQUIRED" => StatusCodes.Status400BadRequest,
            "NAV_PRODUCTION_ORDER_NOT_FOUND" => StatusCodes.Status404NotFound,
            _ => StatusCodes.Status409Conflict
        };
        return Rejected(statusCode, exception.Code, exception.Message);
    }

    private static IResult Rejected(int statusCode, string code, string detail) =>
        Results.Problem(
            statusCode: statusCode,
            title: "Preparación de orden NAV rechazada",
            detail: detail,
            extensions: new Dictionary<string, object?> { ["code"] = code });

    private static IResult Unavailable(string code, string detail) =>
        Results.Problem(
            statusCode: StatusCodes.Status503ServiceUnavailable,
            title: "Preparación de orden NAV no disponible",
            detail: detail,
            extensions: new Dictionary<string, object?> { ["code"] = code });

    private static ProductionOrderSelectionResponse ToResponse(
        ProductionOrderSelectionRecord order) =>
        new(
            order.ProductionOrderId,
            order.OrderNumber,
            order.ProductNumber,
            order.ProductDescription,
            order.LotNumber,
            order.TargetQuantity,
            order.GoodQuantity,
            order.ReservedQuantity,
            order.ScrapQuantity,
            order.RunTimeMinutes,
            order.State,
            order.ImportedAtUtc);
}
