namespace Ebir.Mes.Application.ProductionOrders;

public sealed class SynchronizeProductionOrder(
    IProductionOrderSource source,
    IProductionOrderSnapshotStore store)
{
    public const int MaximumDetailRecords = 100;
    public const int MaximumEnvironmentCodeLength = 30;
    public const int MaximumCompanyCodeLength = 50;
    public const int MaximumOrderNumberLength = 20;
    public const int MaximumLotNumberLength = 50;

    public async Task<ProductionOrderSynchronizationResult> ExecuteAsync(
        ProductionOrderSynchronizationCommand command,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(command);
        var environmentCode = NormalizeRequiredCode(
            command.EnvironmentCode,
            MaximumEnvironmentCodeLength,
            "NAV_ENVIRONMENT_INVALID",
            "El entorno NAV no es válido.");
        var companyCode = NormalizeRequiredCode(
            command.CompanyCode,
            MaximumCompanyCodeLength,
            "NAV_COMPANY_INVALID",
            "La empresa NAV no es válida.");
        var orderNumber = NormalizeRequiredCode(
            command.OrderNumber,
            MaximumOrderNumberLength,
            "NAV_ORDER_NUMBER_INVALID",
            "El número de orden NAV no es válido.");

        if (command.SynchronizationId == Guid.Empty)
        {
            throw Rejected(
                "NAV_SYNCHRONIZATION_ID_REQUIRED",
                "La correlación de sincronización es obligatoria.");
        }

        var order = await source.ReadOrderAsync(
            ProductionOrderStatus.Released,
            orderNumber,
            cancellationToken);
        if (order is null)
        {
            throw Rejected(
                "NAV_PRODUCTION_ORDER_NOT_FOUND",
                "La orden lanzada no existe en NAV.");
        }

        var lotTask = source.ReadLotAsync(orderNumber, cancellationToken);
        var linesTask = source.ReadLinesAsync(
            ProductionOrderStatus.Released,
            orderNumber,
            MaximumDetailRecords,
            cancellationToken);
        var routingTask = source.ReadRoutingAsync(
            orderNumber,
            MaximumDetailRecords,
            cancellationToken);
        var componentsTask = source.ReadComponentsAsync(
            ProductionOrderStatus.Released,
            orderNumber,
            MaximumDetailRecords,
            cancellationToken);
        await Task.WhenAll(lotTask, linesTask, routingTask, componentsTask);

        var lot = await lotTask;
        var lines = await linesTask;
        var routing = await routingTask;
        var components = await componentsTask;
        ValidateSnapshot(orderNumber, order, lot, lines, routing, components);

        var snapshot = new ProductionOrderSnapshot(
            environmentCode,
            companyCode,
            lot!.LotNumber.Trim(),
            order,
            lines[0],
            routing
                .OrderBy(step => step.RoutingReferenceNumber)
                .ThenBy(step => step.RoutingNumber, StringComparer.Ordinal)
                .ThenBy(step => step.OperationNumber, StringComparer.Ordinal)
                .ToArray(),
            components
                .OrderBy(component => component.ProductionOrderLineNumber)
                .ThenBy(component => component.LineNumber)
                .ToArray());

        return await store.SaveAsync(
            snapshot,
            command.SynchronizationId,
            cancellationToken);
    }

    private static void ValidateSnapshot(
        string orderNumber,
        ProductionOrderRecord order,
        ProductionOrderLotRecord? lot,
        IReadOnlyList<ProductionOrderLineRecord> lines,
        IReadOnlyList<ProductionOrderRoutingStepRecord> routing,
        IReadOnlyList<ProductionOrderComponentRecord> components)
    {
        if (!string.Equals(order.OrderNumber, orderNumber, StringComparison.Ordinal))
        {
            throw Rejected(
                "NAV_ORDER_KEY_MISMATCH",
                "NAV devolvió una cabecera de otra orden.");
        }

        if (lot is null || string.IsNullOrWhiteSpace(lot.LotNumber))
        {
            throw Rejected(
                "NAV_PRODUCTION_ORDER_LOT_REQUIRED",
                "La orden lanzada no tiene un lote de salida asignado en NAV.");
        }

        if (lot.LotNumber.Trim().Length > MaximumLotNumberLength)
        {
            throw Rejected(
                "NAV_PRODUCTION_ORDER_LOT_INVALID",
                "El lote de salida NAV supera la longitud admitida por MES.");
        }

        if (!string.Equals(lot.OrderNumber, orderNumber, StringComparison.Ordinal) ||
            !string.Equals(lot.ProductNumber, order.ProductNumber, StringComparison.Ordinal))
        {
            throw Rejected(
                "NAV_PRODUCTION_ORDER_LOT_MISMATCH",
                "El lote NAV no corresponde a la orden y producto solicitados.");
        }

        if (lines.Count != 1)
        {
            throw Rejected(
                "NAV_SINGLE_LINE_ORDER_REQUIRED",
                "El piloto requiere exactamente una línea por orden NAV.");
        }

        if (routing.Count == MaximumDetailRecords ||
            components.Count == MaximumDetailRecords)
        {
            throw Rejected(
                "NAV_ORDER_DETAIL_PAGE_LIMIT_REACHED",
                "La orden alcanza el límite de detalle y no puede sincronizarse parcialmente.");
        }

        var line = lines[0];
        if (!BelongsToReleasedOrder(line.OrderNumber, line.Status, orderNumber) ||
            !string.Equals(
                line.ProductNumber,
                order.ProductNumber,
                StringComparison.Ordinal))
        {
            throw Rejected(
                "NAV_ORDER_LINE_MISMATCH",
                "La línea NAV no coincide con la cabecera de la orden.");
        }

        if (routing.Any(step =>
                !string.Equals(
                    step.OrderNumber,
                    orderNumber,
                    StringComparison.Ordinal)) ||
            routing.Select(step => step.RoutingReferenceNumber).Distinct().Count() > 1)
        {
            throw Rejected(
                "NAV_ORDER_ROUTING_MISMATCH",
                "La ruta NAV no corresponde a una única línea de la orden.");
        }

        if (components.Any(component =>
                !BelongsToReleasedOrder(
                    component.OrderNumber,
                    component.Status,
                    orderNumber)) ||
            components
                .Select(component => component.ProductionOrderLineNumber)
                .Distinct()
                .Count() > 1)
        {
            throw Rejected(
                "NAV_ORDER_COMPONENT_MISMATCH",
                "Los componentes NAV no corresponden a una única línea de la orden.");
        }
    }

    private static bool BelongsToReleasedOrder(
        string candidateOrderNumber,
        ProductionOrderStatus status,
        string orderNumber) =>
        status == ProductionOrderStatus.Released &&
        string.Equals(
            candidateOrderNumber,
            orderNumber,
            StringComparison.Ordinal);

    private static string NormalizeRequiredCode(
        string value,
        int maximumLength,
        string errorCode,
        string errorMessage)
    {
        var normalized = value?.Trim().ToUpperInvariant() ?? string.Empty;
        if (normalized.Length == 0 || normalized.Length > maximumLength)
        {
            throw Rejected(errorCode, errorMessage);
        }

        return normalized;
    }

    private static ProductionOrderSynchronizationRejectedException Rejected(
        string code,
        string message) =>
        new(code, message);
}
