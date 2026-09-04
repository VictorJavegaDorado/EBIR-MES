using Ebir.Mes.Application.ProductionOrders;
using Xunit;

namespace Ebir.Mes.Application.Tests.ProductionOrders;

public sealed class PrepareProductionOrderTests
{
    [Theory]
    [InlineData(ProductionOrderPromotionOutcome.Created)]
    [InlineData(ProductionOrderPromotionOutcome.Unchanged)]
    public async Task ExecuteAsync_synchronizes_promotes_and_returns_selectable_order(
        ProductionOrderPromotionOutcome promotionOutcome)
    {
        var synchronizationStore = new SynchronizationStore();
        var promotionStore = new PromotionStore(promotionOutcome);
        var expected = OrderSelection();
        var correlation = Guid.NewGuid();
        var useCase = new PrepareProductionOrder(
            new SynchronizeProductionOrder(new Source(), synchronizationStore),
            new PromoteProductionOrder(promotionStore),
            new Reader(expected));

        var result = await useCase.ExecuteAsync(
            new("EBIRTEST", "EBIR", "FL26-00007", correlation),
            CancellationToken.None);

        Assert.Same(expected, result.Order);
        Assert.Equal("010", promotionStore.Command!.OperationNumber);
        Assert.Equal(correlation, promotionStore.Command.CorrelationId);
        Assert.Equal(42, promotionStore.Command.InboundOrderId);
        Assert.Equal(promotionOutcome, result.PromotionOutcome);
    }

    [Fact]
    public async Task ExecuteAsync_rejects_an_order_that_requires_review()
    {
        var useCase = new PrepareProductionOrder(
            new SynchronizeProductionOrder(new Source(), new SynchronizationStore()),
            new PromoteProductionOrder(
                new PromotionStore(ProductionOrderPromotionOutcome.ReviewRequired)),
            new Reader(OrderSelection()));

        var exception = await Assert.ThrowsAsync<ProductionOrderPreparationRejectedException>(
            () => useCase.ExecuteAsync(
                new("EBIRTEST", "EBIR", "FL26-00007", Guid.NewGuid()),
                CancellationToken.None));

        Assert.Equal("NAV_PRODUCTION_ORDER_REVIEW_REQUIRED", exception.Code);
    }

    [Fact]
    public async Task ExecuteAsync_rejects_a_promoted_order_that_is_not_selectable()
    {
        var useCase = new PrepareProductionOrder(
            new SynchronizeProductionOrder(new Source(), new SynchronizationStore()),
            new PromoteProductionOrder(
                new PromotionStore(ProductionOrderPromotionOutcome.Created)),
            new Reader(null));

        var exception = await Assert.ThrowsAsync<ProductionOrderPreparationRejectedException>(
            () => useCase.ExecuteAsync(
                new("EBIRTEST", "EBIR", "FL26-00007", Guid.NewGuid()),
                CancellationToken.None));

        Assert.Equal("PRODUCTION_ORDER_NOT_SELECTABLE", exception.Code);
    }

    private static ProductionOrderSelectionRecord OrderSelection() => new(
        84, "FL26-00007", "ITEM-01", "PRODUCTO PILOTO", "FL2600007",
        20, 0, 0, 0, 2m, "IMPORTADA", DateTime.UtcNow);

    private sealed class Source : IProductionOrderSource
    {
        public Task<IReadOnlyList<ProductionOrderRecord>> ReadAsync(
            ProductionOrderStatus status,
            int maximumRecords,
            CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<ProductionOrderRecord>>([Order()]);

        public Task<ProductionOrderRecord?> ReadOrderAsync(
            ProductionOrderStatus status,
            string orderNumber,
            CancellationToken cancellationToken) =>
            Task.FromResult<ProductionOrderRecord?>(Order());

        public Task<ProductionOrderLotRecord?> ReadLotAsync(
            string orderNumber,
            CancellationToken cancellationToken) =>
            Task.FromResult<ProductionOrderLotRecord?>(
                new("FL26-00007", "ITEM-01", "FL2600007"));

        public Task<IReadOnlyList<ProductionOrderLineRecord>> ReadLinesAsync(
            ProductionOrderStatus status,
            string orderNumber,
            int maximumRecords,
            CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<ProductionOrderLineRecord>>([new(
                "FL26-00007", ProductionOrderStatus.Released, "ITEM-01", "",
                "PRODUCTO PILOTO", "FABRICA", 20m, 0m, 20m, 0m, null,
                new DateOnly(2026, 9, 4), null, "BOM-01")]);

        public Task<IReadOnlyList<ProductionOrderRoutingStepRecord>> ReadRoutingAsync(
            string orderNumber,
            int maximumRecords,
            CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<ProductionOrderRoutingStepRecord>>([new(
                "FL26-00007", 10000, "RUTA-01", "010", "", "",
                ProductionRoutingStepType.WorkCenter,
                SynchronizeProductionOrder.PaternaCapacityNumber,
                "BANCO DE MONTAJE", null, null, 0m, 2m, 0m, 0m, 0m, "",
                0m, ProductionRoutingStatus.Planned, "FABRICA", false)]);

        public Task<IReadOnlyList<ProductionOrderComponentRecord>> ReadComponentsAsync(
            ProductionOrderStatus status,
            string orderNumber,
            int maximumRecords,
            CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<ProductionOrderComponentRecord>>([]);

        public Task<IReadOnlyList<ProductionOrderPalletFormatRecord>> ReadPalletFormatsAsync(
            string productNumber,
            string formatCode,
            int maximumRecords,
            CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<ProductionOrderPalletFormatRecord>>(
                [new("ITEM-01", "POK", 20m)]);

        public Task<IReadOnlyList<ProductionOrderProductPostingGroupRecord>>
            ReadProductPostingGroupsAsync(
                string productNumber,
                int maximumRecords,
                CancellationToken cancellationToken) =>
                Task.FromResult<IReadOnlyList<ProductionOrderProductPostingGroupRecord>>(
                    [new("ITEM-01", "P_MATPRIMA")]);

        private static ProductionOrderRecord Order() => new(
            "FL26-00007", ProductionOrderStatus.Released, "PRODUCTO PILOTO",
            "ITEM-01", "RUTA-01", 20m, "FABRICA", new DateOnly(2026, 9, 4),
            null, null);
    }

    private sealed class SynchronizationStore : IProductionOrderSnapshotStore
    {
        public Task<ProductionOrderSynchronizationResult> SaveAsync(
            ProductionOrderSnapshot snapshot,
            Guid synchronizationId,
            CancellationToken cancellationToken) =>
            Task.FromResult(new ProductionOrderSynchronizationResult(
                42,
                ProductionOrderSynchronizationOutcome.Created));
    }

    private sealed class PromotionStore(ProductionOrderPromotionOutcome outcome)
        : IProductionOrderPromotionStore
    {
        public ProductionOrderPromotionCommand? Command { get; private set; }

        public Task<ProductionOrderPromotionResult> PromoteAsync(
            ProductionOrderPromotionCommand command,
            CancellationToken cancellationToken)
        {
            Command = command;
            return Task.FromResult(new ProductionOrderPromotionResult(84, outcome));
        }
    }

    private sealed class Reader(ProductionOrderSelectionRecord? order)
        : IPreparedProductionOrderReader
    {
        public Task<ProductionOrderSelectionRecord?> ReadAsync(
            long productionOrderId,
            CancellationToken cancellationToken) => Task.FromResult(order);
    }
}
