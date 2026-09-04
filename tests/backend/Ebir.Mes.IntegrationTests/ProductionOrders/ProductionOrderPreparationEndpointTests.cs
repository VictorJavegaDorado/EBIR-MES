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

public sealed class ProductionOrderPreparationEndpointTests
{
    [Fact]
    public async Task PrepareAsync_when_disabled_does_not_resolve_use_case()
    {
        using var factory = new WebApplicationFactory<Program>();
        using var response = await factory.CreateClient().PostAsJsonAsync(
            "/api/production-orders/prepare",
            Request());
        using var body = await ReadBodyAsync(response);

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.Equal(
            "NAV_PRODUCTION_ORDER_PREPARATION_DISABLED",
            body.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task PrepareAsync_returns_the_selectable_order()
    {
        var promotionStore = new PromotionStore();
        using var factory = EnabledFactory(
            new PrepareProductionOrder(
                new SynchronizeProductionOrder(new Source(), new SynchronizationStore()),
                new PromoteProductionOrder(promotionStore),
                new Reader()));
        var correlation = Guid.NewGuid();
        using var response = await factory.CreateClient().PostAsJsonAsync(
            "/api/production-orders/prepare",
            Request(correlation));
        using var body = await ReadBodyAsync(response);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(84, body.RootElement.GetProperty("productionOrderId").GetInt64());
        Assert.Equal("FL26-00007", body.RootElement.GetProperty("orderNumber").GetString());
        Assert.Equal("010", promotionStore.Command!.OperationNumber);
        Assert.Equal(correlation, promotionStore.Command.CorrelationId);
    }

    private static WebApplicationFactory<Program> EnabledFactory(
        PrepareProductionOrder useCase) =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment("Testing");
            builder.ConfigureAppConfiguration(configuration =>
                configuration.AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["Navision:ProductionOrderPreparationEnabled"] = "true",
                    ["Navision:Environment"] = "EBIRTEST",
                    ["Navision:Company"] = "EBIR",
                    ["Navision:ServiceRoot"] =
                        "http://NAVISION2.EBIR.LOCAL:7147/EbirTest/WS/",
                    ["Navision:RequestTimeoutSeconds"] = "30",
                    ["Navision:MaximumReadAttempts"] = "3"
                }));
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<PrepareProductionOrder>();
                services.AddSingleton(useCase);
            });
        });

    private static object Request(Guid? correlation = null) => new
    {
        orderNumber = "FL26-00007",
        correlationId = correlation ?? Guid.NewGuid()
    };

    private static async Task<JsonDocument> ReadBodyAsync(
        HttpResponseMessage response) =>
        JsonDocument.Parse(await response.Content.ReadAsStringAsync());

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

    private sealed class PromotionStore : IProductionOrderPromotionStore
    {
        public ProductionOrderPromotionCommand? Command { get; private set; }

        public Task<ProductionOrderPromotionResult> PromoteAsync(
            ProductionOrderPromotionCommand command,
            CancellationToken cancellationToken)
        {
            Command = command;
            return Task.FromResult(new ProductionOrderPromotionResult(
                84,
                ProductionOrderPromotionOutcome.Created));
        }
    }

    private sealed class Reader : IPreparedProductionOrderReader
    {
        public Task<ProductionOrderSelectionRecord?> ReadAsync(
            long productionOrderId,
            CancellationToken cancellationToken) =>
            Task.FromResult<ProductionOrderSelectionRecord?>(new(
                productionOrderId, "FL26-00007", "ITEM-01", "PRODUCTO PILOTO",
                "FL2600007", 20, 0, 0, 0, 2m, "IMPORTADA", DateTime.UtcNow));
    }
}
