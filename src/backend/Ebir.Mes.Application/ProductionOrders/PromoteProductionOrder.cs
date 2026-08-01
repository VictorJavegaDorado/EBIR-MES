namespace Ebir.Mes.Application.ProductionOrders;

public sealed class PromoteProductionOrder(IProductionOrderPromotionStore store)
{
    public Task<ProductionOrderPromotionResult> ExecuteAsync(
        ProductionOrderPromotionCommand command,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(command);
        var normalized = command with
        {
            Lot = Normalize(command.Lot),
            OperationNumber = Normalize(command.OperationNumber).ToUpperInvariant(),
            LotProvidedBy = Normalize(command.LotProvidedBy)
        };
        if (normalized.InboundOrderId <= 0)
            throw Rejected("NAV_INBOUND_ORDER_INVALID", "La orden de entrada no es válida.");
        if (normalized.CorrelationId == Guid.Empty)
            throw Rejected("NAV_PROMOTION_ID_REQUIRED", "La correlación de promoción es obligatoria.");
        Validate(normalized.Lot, 50, "NAV_PROMOTION_LOT_INVALID", "El lote es obligatorio y admite 50 caracteres.");
        Validate(normalized.OperationNumber, 30, "NAV_PROMOTION_OPERATION_INVALID", "La operación productiva es obligatoria y admite 30 caracteres.");
        Validate(normalized.LotProvidedBy, 256, "NAV_PROMOTION_LOT_PROVIDER_INVALID", "Debe identificarse quién proporcionó el lote.");
        return store.PromoteAsync(normalized, cancellationToken);
    }

    private static string Normalize(string? value) => value?.Trim() ?? string.Empty;

    private static void Validate(string value, int maximum, string code, string message)
    {
        if (value.Length is 0 || value.Length > maximum)
            throw Rejected(code, message);
    }

    private static ProductionOrderPromotionRejectedException Rejected(
        string code,
        string message) => new(code, message);
}
