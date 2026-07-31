using Ebir.Mes.Application.ProductionOrders;

namespace Ebir.Mes.Api.Endpoints.ProductionOrders;

public static class ProductionOrderSynchronizationEndpoints
{
    public static IEndpointRouteBuilder MapProductionOrderSynchronizationEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost(
                "/api/admin/production-orders/synchronize",
                HandleAsync)
            .WithName("SynchronizeProductionOrder")
            .WithSummary(
                "Sincroniza bajo demanda una orden lanzada exacta desde NAV.")
            .Produces<SynchronizeProductionOrderResponse>(200)
            .ProducesProblem(400)
            .ProducesProblem(404)
            .ProducesProblem(409)
            .ProducesProblem(503);
        return endpoints;
    }

    private static async Task<IResult> HandleAsync(
        SynchronizeProductionOrderRequest request,
        IServiceProvider services,
        IConfiguration applicationConfiguration,
        ILoggerFactory loggerFactory,
        CancellationToken cancellationToken)
    {
        var logger = loggerFactory.CreateLogger("ProductionOrderSynchronization");
        var configuration = ProductionOrderSynchronizationConfiguration.Read(
            applicationConfiguration);
        if (!configuration.Enabled)
        {
            return Unavailable(
                "NAV_PRODUCTION_ORDER_SYNCHRONIZATION_DISABLED",
                "La sincronizaci?n manual de ?rdenes NAV est? desactivada.");
        }

        logger.LogInformation(
            "Production order synchronization requested for order {OrderNumber} with correlation {CorrelationId}.",
            request.OrderNumber,
            request.CorrelationId);

        try
        {
            configuration.CreateNavisionOptions();
            var useCase = services.GetRequiredService<SynchronizeProductionOrder>();
            var result = await useCase.ExecuteAsync(
                new ProductionOrderSynchronizationCommand(
                    configuration.EnvironmentCode,
                    configuration.CompanyCode,
                    request.OrderNumber,
                    request.CorrelationId),
                cancellationToken);
            var outcome = ToContractOutcome(result.Outcome);
            logger.LogInformation(
                "Production order synchronization finished with outcome {Outcome}, inbound order {InboundOrderId} and correlation {CorrelationId}.",
                outcome,
                result.InboundOrderId,
                request.CorrelationId);
            return Results.Ok(new SynchronizeProductionOrderResponse(
                result.InboundOrderId,
                outcome,
                request.CorrelationId));
        }
        catch (ProductionOrderSynchronizationRejectedException exception)
        {
            logger.LogWarning(
                "Production order synchronization rejected with code {Code} and correlation {CorrelationId}.",
                exception.Code,
                request.CorrelationId);
            return Rejected(exception);
        }
        catch (Exception exception)
            when (exception is ProductionOrderSourceUnavailableException or
                  ProductionOrderSynchronizationUnavailableException)
        {
            logger.LogError(
                "Production order synchronization unavailable for correlation {CorrelationId}.",
                request.CorrelationId);
            return Unavailable(
                "NAV_PRODUCTION_ORDER_SYNCHRONIZATION_UNAVAILABLE",
                "No se puede sincronizar la orden NAV en este momento.");
        }
    }

    private static IResult Rejected(
        ProductionOrderSynchronizationRejectedException exception)
    {
        var statusCode = exception.Code switch
        {
            "NAV_ENVIRONMENT_INVALID" or
            "NAV_COMPANY_INVALID" or
            "NAV_ORDER_NUMBER_INVALID" or
            "NAV_SYNCHRONIZATION_ID_REQUIRED" =>
                StatusCodes.Status400BadRequest,
            "NAV_PRODUCTION_ORDER_NOT_FOUND" => StatusCodes.Status404NotFound,
            _ => StatusCodes.Status409Conflict
        };
        return Results.Problem(
            statusCode: statusCode,
            title: "Sincronizaci?n de orden NAV rechazada",
            detail: exception.Message,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = exception.Code
            });
    }

    private static IResult Unavailable(string code, string detail) =>
        Results.Problem(
            statusCode: StatusCodes.Status503ServiceUnavailable,
            title: "Sincronizaci?n de orden NAV no disponible",
            detail: detail,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = code
            });

    private static string ToContractOutcome(
        ProductionOrderSynchronizationOutcome outcome) =>
        outcome switch
        {
            ProductionOrderSynchronizationOutcome.Created => "CREADA",
            ProductionOrderSynchronizationOutcome.Updated => "ACTUALIZADA",
            ProductionOrderSynchronizationOutcome.Unchanged => "SIN_CAMBIOS",
            _ => throw new InvalidOperationException(
                "Unknown production order synchronization outcome.")
        };
}
