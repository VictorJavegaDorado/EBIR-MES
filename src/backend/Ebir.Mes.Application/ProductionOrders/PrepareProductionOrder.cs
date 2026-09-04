namespace Ebir.Mes.Application.ProductionOrders;

public sealed class PrepareProductionOrder(
    SynchronizeProductionOrder synchronize,
    PromoteProductionOrder promote,
    IPreparedProductionOrderReader reader)
{
    public async Task<PrepareProductionOrderResult> ExecuteAsync(
        PrepareProductionOrderCommand command,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(command);

        var synchronization = await synchronize.ExecuteAsync(
            new ProductionOrderSynchronizationCommand(
                command.EnvironmentCode,
                command.CompanyCode,
                command.OrderNumber,
                command.CorrelationId),
            cancellationToken);

        if (string.IsNullOrWhiteSpace(synchronization.PaternaOperationNumber))
        {
            throw new ProductionOrderPreparationRejectedException(
                "NAV_PATERNA_OPERATION_NOT_AVAILABLE",
                "La operación productiva de Paterna no está disponible.");
        }

        var promotion = await promote.ExecuteAsync(
            new ProductionOrderPromotionCommand(
                synchronization.InboundOrderId,
                synchronization.PaternaOperationNumber,
                command.CorrelationId),
            cancellationToken);
        if (promotion.Outcome == ProductionOrderPromotionOutcome.ReviewRequired)
        {
            throw new ProductionOrderPreparationRejectedException(
                "NAV_PRODUCTION_ORDER_REVIEW_REQUIRED",
                "La orden ha cambiado y requiere revisión antes de producir.");
        }

        var order = await reader.ReadAsync(
            promotion.ProductionOrderId,
            cancellationToken);
        if (order is null)
        {
            throw new ProductionOrderPreparationRejectedException(
                "PRODUCTION_ORDER_NOT_SELECTABLE",
                "La orden preparada no está disponible para producción.");
        }

        return new PrepareProductionOrderResult(
            order,
            synchronization.Outcome,
            promotion.Outcome);
    }
}
