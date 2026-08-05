namespace Ebir.Mes.Application.ProductionOrders;

public interface IProductionOrderSource
{
    Task<IReadOnlyList<ProductionOrderRecord>> ReadAsync(
        ProductionOrderStatus status,
        int maximumRecords,
        CancellationToken cancellationToken);

    Task<ProductionOrderRecord?> ReadOrderAsync(
        ProductionOrderStatus status,
        string orderNumber,
        CancellationToken cancellationToken);

    Task<ProductionOrderLotRecord?> ReadLotAsync(
        string orderNumber,
        CancellationToken cancellationToken);

    Task<IReadOnlyList<ProductionOrderLineRecord>> ReadLinesAsync(
        ProductionOrderStatus status,
        string orderNumber,
        int maximumRecords,
        CancellationToken cancellationToken);

    Task<IReadOnlyList<ProductionOrderRoutingStepRecord>> ReadRoutingAsync(
        string orderNumber,
        int maximumRecords,
        CancellationToken cancellationToken);

    Task<IReadOnlyList<ProductionOrderComponentRecord>> ReadComponentsAsync(
        ProductionOrderStatus status,
        string orderNumber,
        int maximumRecords,
        CancellationToken cancellationToken);

    Task<IReadOnlyList<ProductionOrderPalletFormatRecord>> ReadPalletFormatsAsync(
        string productNumber,
        string formatCode,
        int maximumRecords,
        CancellationToken cancellationToken);

    Task<IReadOnlyList<ProductionOrderProductPostingGroupRecord>>
        ReadProductPostingGroupsAsync(
            string productNumber,
            int maximumRecords,
            CancellationToken cancellationToken);
}
