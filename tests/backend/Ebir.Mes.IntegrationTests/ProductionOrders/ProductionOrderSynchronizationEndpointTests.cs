using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Ebir.Mes.Application.ProductionOrders;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Xunit;

namespace Ebir.Mes.IntegrationTests.ProductionOrders;

public sealed class ProductionOrderSynchronizationEndpointTests
{
    [Fact]
    public async Task SynchronizeAsync_WhenDisabled_DoesNotResolveAdapters()
    {
        using var factory = new WebApplicationFactory<Program>();
        using var client = factory.CreateClient();

        using var response = await client.PostAsJsonAsync(
            "/api/admin/production-orders/synchronize",
            Request());
        using var body = await ReadBodyAsync(response);

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.Equal(
            "NAV_PRODUCTION_ORDER_SYNCHRONIZATION_DISABLED",
            body.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task SynchronizeAsync_ReturnsCreatedContractFromServerConfiguration()
    {
        var source = new StubSource { Order = Order() };
        var store = new StubStore(new(
            42,
            ProductionOrderSynchronizationOutcome.Created));
        using var factory = CreateEnabledFactory(source, store);
        using var client = factory.CreateClient();
        var correlationId = Guid.NewGuid();

        using var response = await client.PostAsJsonAsync(
            "/api/admin/production-orders/synchronize",
            Request(correlationId));
        using var body = await ReadBodyAsync(response);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(42, body.RootElement.GetProperty("inboundOrderId").GetInt64());
        Assert.Equal("CREADA", body.RootElement.GetProperty("outcome").GetString());
        Assert.Equal(
            correlationId,
            body.RootElement.GetProperty("correlationId").GetGuid());
        Assert.Equal("EBIRTEST", store.Snapshot!.EnvironmentCode);
        Assert.Equal("EBIR", store.Snapshot.CompanyCode);
        Assert.Equal(correlationId, store.SynchronizationId);
    }

    [Fact]
    public async Task SynchronizeAsync_InvalidRequest_ReturnsSafeBadRequest()
    {
        using var factory = CreateEnabledFactory(
            new StubSource(),
            new StubStore(new(1, ProductionOrderSynchronizationOutcome.Created)));
        using var client = factory.CreateClient();

        using var response = await client.PostAsJsonAsync(
            "/api/admin/production-orders/synchronize",
            new
            {
                orderNumber = "",
                correlationId = Guid.NewGuid()
            });
        using var body = await ReadBodyAsync(response);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal(
            "NAV_ORDER_NUMBER_INVALID",
            body.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task SynchronizeAsync_MissingReleasedOrder_ReturnsNotFound()
    {
        using var factory = CreateEnabledFactory(
            new StubSource(),
            new StubStore(new(1, ProductionOrderSynchronizationOutcome.Created)));
        using var client = factory.CreateClient();

        using var response = await client.PostAsJsonAsync(
            "/api/admin/production-orders/synchronize",
            Request());
        using var body = await ReadBodyAsync(response);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.Equal(
            "NAV_PRODUCTION_ORDER_NOT_FOUND",
            body.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task SynchronizeAsync_StoreRejection_ReturnsSafeConflict()
    {
        var source = new StubSource { Order = Order() };
        using var factory = CreateEnabledFactory(source, new RejectingStore());
        using var client = factory.CreateClient();

        using var response = await client.PostAsJsonAsync(
            "/api/admin/production-orders/synchronize",
            Request());
        var content = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Contains(
            "NAV_SYNCHRONIZATION_ID_PARAMETER_MISMATCH",
            content,
            StringComparison.Ordinal);
        Assert.DoesNotContain("55503", content, StringComparison.Ordinal);
    }

    [Fact]
    public async Task SynchronizeAsync_SourceFailure_ReturnsSafeServiceUnavailable()
    {
        using var factory = CreateEnabledFactory(
            new UnavailableSource(),
            new StubStore(new(1, ProductionOrderSynchronizationOutcome.Created)));
        using var client = factory.CreateClient();

        using var response = await client.PostAsJsonAsync(
            "/api/admin/production-orders/synchronize",
            Request());
        var content = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.Contains(
            "NAV_PRODUCTION_ORDER_SYNCHRONIZATION_UNAVAILABLE",
            content,
            StringComparison.Ordinal);
        Assert.DoesNotContain(
            "synthetic SOAP detail",
            content,
            StringComparison.Ordinal);
    }

    private static WebApplicationFactory<Program> CreateEnabledFactory(
        IProductionOrderSource source,
        IProductionOrderSnapshotStore store) =>
        new WebApplicationFactory<Program>()
            .WithWebHostBuilder(builder =>
            {
                builder.UseEnvironment("Testing");
                builder.ConfigureAppConfiguration(configuration =>
                    configuration.AddInMemoryCollection(new Dictionary<string, string?>
                    {
                        ["Navision:ProductionOrderSynchronizationEnabled"] = "true",
                        ["Navision:Environment"] = "EBIRTEST",
                        ["Navision:Company"] = "EBIR",
                        ["Navision:ServiceRoot"] =
                            "http://nav.test/EBIRTEST/WS/EBIR",
                        ["Navision:RequestTimeoutSeconds"] = "30",
                        ["Navision:MaximumReadAttempts"] = "3"
                    }));
                builder.ConfigureTestServices(services =>
                {
                    services.RemoveAll<IProductionOrderSource>();
                    services.RemoveAll<IProductionOrderSnapshotStore>();
                    services.AddSingleton(source);
                    services.AddSingleton(store);
                });
            });

    private static object Request(Guid? correlationId = null) => new
    {
        orderNumber = "OF26-00042",
        correlationId = correlationId ?? Guid.NewGuid()
    };

    private static async Task<JsonDocument> ReadBodyAsync(
        HttpResponseMessage response) =>
        JsonDocument.Parse(await response.Content.ReadAsStringAsync());

    private static ProductionOrderRecord Order() => new(
        "OF26-00042",
        ProductionOrderStatus.Released,
        "PRODUCTO",
        "ITEM-01",
        "RUTA-01",
        100m,
        "FABRICA",
        new DateOnly(2026, 7, 31),
        null,
        null);

    private static ProductionOrderLineRecord Line() => new(
        "OF26-00042",
        ProductionOrderStatus.Released,
        "ITEM-01",
        "",
        "PRODUCTO",
        "FABRICA",
        100m,
        0m,
        100m,
        0m,
        null,
        new DateOnly(2026, 7, 31),
        null,
        "BOM-01");

    private class StubSource : IProductionOrderSource
    {
        public ProductionOrderRecord? Order { get; init; }

        public Task<IReadOnlyList<ProductionOrderRecord>> ReadAsync(
            ProductionOrderStatus status,
            int maximumRecords,
            CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<ProductionOrderRecord>>(
                Order is null ? [] : [Order]);

        public virtual Task<ProductionOrderRecord?> ReadOrderAsync(
            ProductionOrderStatus status,
            string orderNumber,
            CancellationToken cancellationToken) =>
            Task.FromResult(Order);

        public Task<ProductionOrderLotRecord?> ReadLotAsync(
            string orderNumber,
            CancellationToken cancellationToken) =>
            Task.FromResult<ProductionOrderLotRecord?>(
                new("OF26-00042", "ITEM-01", "FL2600042"));

        public Task<IReadOnlyList<ProductionOrderLineRecord>> ReadLinesAsync(
            ProductionOrderStatus status,
            string orderNumber,
            int maximumRecords,
            CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<ProductionOrderLineRecord>>([Line()]);

        public Task<IReadOnlyList<ProductionOrderRoutingStepRecord>> ReadRoutingAsync(
            string orderNumber,
            int maximumRecords,
            CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<ProductionOrderRoutingStepRecord>>(
                [new(
                    "OF26-00042", 10000, "RUTA-01", "010", "", "",
                    ProductionRoutingStepType.WorkCenter,
                    SynchronizeProductionOrder.PaternaCapacityNumber,
                    "BANCO DE MONTAJE", null, null, 0m, 2m, 0m, 0m, 0m, "",
                    0m, ProductionRoutingStatus.NotStarted, "FABRICA", false)]);

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
    }

    private sealed class UnavailableSource : StubSource
    {
        public override Task<ProductionOrderRecord?> ReadOrderAsync(
            ProductionOrderStatus status,
            string orderNumber,
            CancellationToken cancellationToken) =>
            throw new ProductionOrderSourceUnavailableException(
                "synthetic SOAP detail");
    }

    private sealed class StubStore(ProductionOrderSynchronizationResult result)
        : IProductionOrderSnapshotStore
    {
        public ProductionOrderSnapshot? Snapshot { get; private set; }
        public Guid SynchronizationId { get; private set; }

        public Task<ProductionOrderSynchronizationResult> SaveAsync(
            ProductionOrderSnapshot snapshot,
            Guid synchronizationId,
            CancellationToken cancellationToken)
        {
            Snapshot = snapshot;
            SynchronizationId = synchronizationId;
            return Task.FromResult(result);
        }
    }

    private sealed class RejectingStore : IProductionOrderSnapshotStore
    {
        public Task<ProductionOrderSynchronizationResult> SaveAsync(
            ProductionOrderSnapshot snapshot,
            Guid synchronizationId,
            CancellationToken cancellationToken) =>
            throw new ProductionOrderSynchronizationRejectedException(
                "NAV_SYNCHRONIZATION_ID_PARAMETER_MISMATCH",
                "La correlaci?n ya se utiliz? con otro snapshot.");
    }
}
