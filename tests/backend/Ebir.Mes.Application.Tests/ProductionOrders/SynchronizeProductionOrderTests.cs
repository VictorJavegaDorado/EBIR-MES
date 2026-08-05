using Ebir.Mes.Application.ProductionOrders;
using Xunit;

namespace Ebir.Mes.Application.Tests.ProductionOrders;

public sealed class SynchronizeProductionOrderTests
{
    [Fact]
    public async Task ExecuteAsync_saves_a_normalized_deterministic_snapshot()
    {
        var source = new StubSource
        {
            Order = Order(),
            Lot = Lot(" FL2600042 "),
            Lines = [Line()],
            Routing = [Route("020", "3"), Route("010")],
            Components = [Component(20000), Component(10000)]
        };
        var store = new StubStore(new(
            42,
            ProductionOrderSynchronizationOutcome.Created));
        var synchronizationId = Guid.NewGuid();

        var result = await new SynchronizeProductionOrder(source, store)
            .ExecuteAsync(
                new(" ebirtest ", " ebir ", " of26-00042 ", synchronizationId),
                CancellationToken.None);

        Assert.Equal(42, result.InboundOrderId);
        Assert.Equal(ProductionOrderSynchronizationOutcome.Created, result.Outcome);
        Assert.NotNull(store.Snapshot);
        Assert.Equal("EBIRTEST", store.Snapshot.EnvironmentCode);
        Assert.Equal("EBIR", store.Snapshot.CompanyCode);
        Assert.Equal("FL2600042", store.Snapshot.LotNumber);
        Assert.Equal(["010", "020"], store.Snapshot.Routing.Select(step => step.OperationNumber));
        Assert.Equal([10000, 20000], store.Snapshot.Components.Select(component => component.LineNumber));
        Assert.Equal("POK", store.Snapshot.PalletFormat.Code);
        Assert.Equal(20m, store.Snapshot.PalletFormat.QuantityPerUnitMeasure);
        Assert.Equal(synchronizationId, store.SynchronizationId);
    }

    [Fact]
    public async Task ExecuteAsync_rejects_a_missing_order_without_saving()
    {
        var source = new StubSource();
        var store = new StubStore(new(1, ProductionOrderSynchronizationOutcome.Created));

        var exception = await Assert.ThrowsAsync<ProductionOrderSynchronizationRejectedException>(
            () => new SynchronizeProductionOrder(source, store).ExecuteAsync(
                Command(),
                CancellationToken.None));

        Assert.Equal("NAV_PRODUCTION_ORDER_NOT_FOUND", exception.Code);
        Assert.Null(store.Snapshot);
    }

    [Fact]
    public async Task ExecuteAsync_rejects_more_than_one_order_line()
    {
        var source = ValidSource();
        source.Lines = [Line(), Line()];

        var exception = await Assert.ThrowsAsync<ProductionOrderSynchronizationRejectedException>(
            () => ExecuteAsync(source));

        Assert.Equal("NAV_SINGLE_LINE_ORDER_REQUIRED", exception.Code);
    }

    [Fact]
    public async Task ExecuteAsync_saves_an_order_without_output_lot_as_pending()
    {
        var source = ValidSource();
        source.Lot = null;
        var store = new StubStore(new(1, ProductionOrderSynchronizationOutcome.Created));

        await new SynchronizeProductionOrder(source, store).ExecuteAsync(
            Command(), CancellationToken.None);

        Assert.Equal(string.Empty, store.Snapshot!.LotNumber);
    }

    [Fact]
    public async Task ExecuteAsync_saves_a_blank_output_lot_as_pending()
    {
        var source = ValidSource();
        source.Lot = Lot("   ");
        var store = new StubStore(new(1, ProductionOrderSynchronizationOutcome.Created));

        await new SynchronizeProductionOrder(source, store).ExecuteAsync(
            Command(), CancellationToken.None);

        Assert.Equal(string.Empty, store.Snapshot!.LotNumber);
    }

    [Fact]
    public async Task ExecuteAsync_rejects_a_lot_from_another_product()
    {
        var source = ValidSource();
        source.Lot = Lot("FL2600042") with { ProductNumber = "OTHER" };

        var exception = await Assert.ThrowsAsync<ProductionOrderSynchronizationRejectedException>(
            () => ExecuteAsync(source));

        Assert.Equal("NAV_PRODUCTION_ORDER_LOT_MISMATCH", exception.Code);
    }

    [Fact]
    public async Task ExecuteAsync_rejects_a_component_from_another_order()
    {
        var source = ValidSource();
        source.Components = [Component(10000) with { OrderNumber = "OTHER" }];

        var exception = await Assert.ThrowsAsync<ProductionOrderSynchronizationRejectedException>(
            () => ExecuteAsync(source));

        Assert.Equal("NAV_ORDER_COMPONENT_MISMATCH", exception.Code);
    }

    [Fact]
    public async Task ExecuteAsync_rejects_a_detail_page_at_the_safety_limit()
    {
        var source = ValidSource();
        source.Routing = Enumerable.Range(1, SynchronizeProductionOrder.MaximumDetailRecords)
            .Select(number => Route(number.ToString("000")))
            .ToArray();

        var exception = await Assert.ThrowsAsync<ProductionOrderSynchronizationRejectedException>(
            () => ExecuteAsync(source));

        Assert.Equal("NAV_ORDER_DETAIL_PAGE_LIMIT_REACHED", exception.Code);
    }

    [Fact]
    public async Task ExecuteAsync_rejects_an_order_without_a_paterna_operation()
    {
        var source = ValidSource();
        source.Routing = [Route("010", "3")];

        var exception = await Assert.ThrowsAsync<ProductionOrderSynchronizationRejectedException>(
            () => ExecuteAsync(source));

        Assert.Equal("NAV_PATERNA_OPERATION_NOT_UNIQUE", exception.Code);
    }

    [Fact]
    public async Task ExecuteAsync_rejects_more_than_one_paterna_operation()
    {
        var source = ValidSource();
        source.Routing = [Route("010"), Route("020")];

        var exception = await Assert.ThrowsAsync<ProductionOrderSynchronizationRejectedException>(
            () => ExecuteAsync(source));

        Assert.Equal("NAV_PATERNA_OPERATION_NOT_UNIQUE", exception.Code);
    }

    [Fact]
    public async Task ExecuteAsync_rejects_a_paterna_operation_without_run_time()
    {
        var source = ValidSource();
        source.Routing = [Route("010") with { RunTime = 0m }];

        var exception = await Assert.ThrowsAsync<ProductionOrderSynchronizationRejectedException>(
            () => ExecuteAsync(source));

        Assert.Equal("NAV_PATERNA_RUN_TIME_INVALID", exception.Code);
    }

    private static Task<ProductionOrderSynchronizationResult> ExecuteAsync(StubSource source) =>
        new SynchronizeProductionOrder(
            source,
            new StubStore(new(1, ProductionOrderSynchronizationOutcome.Unchanged)))
        .ExecuteAsync(Command(), CancellationToken.None);

    [Fact]
    public async Task ExecuteAsync_rejects_missing_or_duplicated_pok_format()
    {
        var source = ValidSource();
        source.PalletFormats = [];
        var missing = await Assert.ThrowsAsync<ProductionOrderSynchronizationRejectedException>(
            () => ExecuteAsync(source));
        Assert.Equal("NAV_PALLET_FORMAT_NOT_UNIQUE", missing.Code);

        source.PalletFormats = [PalletFormat(), PalletFormat()];
        var duplicated = await Assert.ThrowsAsync<ProductionOrderSynchronizationRejectedException>(
            () => ExecuteAsync(source));
        Assert.Equal("NAV_PALLET_FORMAT_NOT_UNIQUE", duplicated.Code);
    }

    [Fact]
    public async Task ExecuteAsync_rejects_non_integer_pok_quantity()
    {
        var source = ValidSource();
        source.PalletFormats = [PalletFormat() with { QuantityPerUnitMeasure = 20.5m }];

        var exception = await Assert.ThrowsAsync<ProductionOrderSynchronizationRejectedException>(
            () => ExecuteAsync(source));

        Assert.Equal("NAV_PALLET_FORMAT_QUANTITY_INVALID", exception.Code);
    }

    private static StubSource ValidSource() => new()
    {
        Order = Order(),
        Lot = Lot("FL2600042"),
        Lines = [Line()],
        Routing = [Route("010")],
        Components = [Component(10000)]
    };

    private static ProductionOrderSynchronizationCommand Command() =>
        new("EBIRTEST", "EBIR", "OF26-00042", Guid.NewGuid());

    private static ProductionOrderRecord Order() => new(
        "OF26-00042", ProductionOrderStatus.Released, "PRODUCTO", "ITEM-01",
        "RUTA-01", 100m, "FABRICA", new(2026, 7, 31), null, null);

    private static ProductionOrderLotRecord Lot(string lotNumber) =>
        new("OF26-00042", "ITEM-01", lotNumber);

    private static ProductionOrderLineRecord Line() => new(
        "OF26-00042", ProductionOrderStatus.Released, "ITEM-01", "", "PRODUCTO",
        "FABRICA", 100m, 0m, 100m, 0m, null, new(2026, 7, 31), null, "BOM-01");

    private static ProductionOrderRoutingStepRecord Route(
        string operation,
        string capacityNumber = SynchronizeProductionOrder.PaternaCapacityNumber) => new(
        "OF26-00042", 10000, "RUTA-01", operation, "", "",
        ProductionRoutingStepType.WorkCenter, capacityNumber, "OPERACION", null, null,
        0m, 1m, 0m, 0m, 0m, "", 0m, ProductionRoutingStatus.Planned,
        "FABRICA", false);

    private static ProductionOrderComponentRecord Component(int lineNumber) => new(
        "OF26-00042", 10000, lineNumber, ProductionOrderStatus.Released, "MAT-01",
        "", "MATERIAL", 1m, 100m, 100m, 0m, "KG",
        ProductionComponentFlushingMethod.Manual, "", "010", "FABRICA", "", 0m,
        false);

    private static ProductionOrderPalletFormatRecord PalletFormat() =>
        new("ITEM-01", "POK", 20m);

    private sealed class StubSource : IProductionOrderSource
    {
        public ProductionOrderRecord? Order { get; set; }
        public ProductionOrderLotRecord? Lot { get; set; }
        public IReadOnlyList<ProductionOrderLineRecord> Lines { get; set; } = [];
        public IReadOnlyList<ProductionOrderRoutingStepRecord> Routing { get; set; } = [];
        public IReadOnlyList<ProductionOrderComponentRecord> Components { get; set; } = [];
        public IReadOnlyList<ProductionOrderPalletFormatRecord> PalletFormats { get; set; } =
            [PalletFormat()];

        public Task<IReadOnlyList<ProductionOrderRecord>> ReadAsync(
            ProductionOrderStatus status, int maximumRecords, CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<ProductionOrderRecord>>(Order is null ? [] : [Order]);

        public Task<ProductionOrderRecord?> ReadOrderAsync(
            ProductionOrderStatus status, string orderNumber, CancellationToken cancellationToken) =>
            Task.FromResult(Order);

        public Task<ProductionOrderLotRecord?> ReadLotAsync(
            string orderNumber, CancellationToken cancellationToken) =>
            Task.FromResult(Lot);

        public Task<IReadOnlyList<ProductionOrderLineRecord>> ReadLinesAsync(
            ProductionOrderStatus status, string orderNumber, int maximumRecords,
            CancellationToken cancellationToken) => Task.FromResult(Lines);

        public Task<IReadOnlyList<ProductionOrderRoutingStepRecord>> ReadRoutingAsync(
            string orderNumber, int maximumRecords, CancellationToken cancellationToken) =>
            Task.FromResult(Routing);

        public Task<IReadOnlyList<ProductionOrderComponentRecord>> ReadComponentsAsync(
            ProductionOrderStatus status, string orderNumber, int maximumRecords,
            CancellationToken cancellationToken) => Task.FromResult(Components);

        public Task<IReadOnlyList<ProductionOrderPalletFormatRecord>> ReadPalletFormatsAsync(
            string productNumber, string formatCode, int maximumRecords,
            CancellationToken cancellationToken) => Task.FromResult(PalletFormats);
    }

    private sealed class StubStore(ProductionOrderSynchronizationResult result)
        : IProductionOrderSnapshotStore
    {
        public ProductionOrderSnapshot? Snapshot { get; private set; }
        public Guid SynchronizationId { get; private set; }

        public Task<ProductionOrderSynchronizationResult> SaveAsync(
            ProductionOrderSnapshot snapshot, Guid synchronizationId,
            CancellationToken cancellationToken)
        {
            Snapshot = snapshot;
            SynchronizationId = synchronizationId;
            return Task.FromResult(result);
        }
    }
}
