using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Ebir.Mes.Api.Endpoints.ProductionOrders;
using Ebir.Mes.Application.ProductionOrders;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Xunit;

namespace Ebir.Mes.IntegrationTests.ProductionOrders;

public sealed class ProductionOrderPromotionEndpointTests
{
    [Fact]
    public async Task PromoteAsync_when_disabled_does_not_resolve_store()
    {
        using var factory = new WebApplicationFactory<Program>();
        using var response = await factory.CreateClient().PostAsJsonAsync(
            "/api/admin/production-orders/promote", Request());
        using var body = await ReadBodyAsync(response);
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.Equal("NAV_PRODUCTION_ORDER_PROMOTION_DISABLED",
            body.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task PromoteAsync_returns_created_contract()
    {
        var store = new StubStore();
        using var factory = EnabledFactory(store);
        var correlation = Guid.NewGuid();
        using var response = await factory.CreateClient().PostAsJsonAsync(
            "/api/admin/production-orders/promote", Request(correlation));
        using var body = await ReadBodyAsync(response);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(42, body.RootElement.GetProperty("productionOrderId").GetInt64());
        Assert.Equal("CREADA", body.RootElement.GetProperty("outcome").GetString());
        Assert.Equal(correlation, store.Command!.CorrelationId);
    }

    [Fact]
    public async Task PromoteAsync_invalid_request_returns_safe_bad_request()
    {
        using var factory = EnabledFactory(new StubStore());
        using var response = await factory.CreateClient().PostAsJsonAsync(
            "/api/admin/production-orders/promote", Request() with { OperationNumber = "" });
        using var body = await ReadBodyAsync(response);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("NAV_PROMOTION_OPERATION_INVALID",
            body.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task PromoteAsync_store_failure_returns_safe_unavailable()
    {
        using var factory = EnabledFactory(new UnavailableStore());
        using var response = await factory.CreateClient().PostAsJsonAsync(
            "/api/admin/production-orders/promote", Request());
        var content = await response.Content.ReadAsStringAsync();
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.Contains("NAV_PRODUCTION_ORDER_PROMOTION_UNAVAILABLE", content);
        Assert.DoesNotContain("synthetic SQL detail", content);
    }

    private static WebApplicationFactory<Program> EnabledFactory(
        IProductionOrderPromotionStore store) =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment("Testing");
            builder.ConfigureAppConfiguration(configuration =>
                configuration.AddInMemoryCollection(new Dictionary<string, string?>
                { ["Navision:ProductionOrderPromotionEnabled"] = "true" }));
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IProductionOrderPromotionStore>();
                services.AddSingleton(store);
            });
        });

    private static PromoteProductionOrderRequest Request(Guid? correlation = null) =>
        new(2, "20", correlation ?? Guid.NewGuid());

    private static async Task<JsonDocument> ReadBodyAsync(HttpResponseMessage response) =>
        JsonDocument.Parse(await response.Content.ReadAsStringAsync());

    private sealed class StubStore : IProductionOrderPromotionStore
    {
        public ProductionOrderPromotionCommand? Command { get; private set; }
        public Task<ProductionOrderPromotionResult> PromoteAsync(
            ProductionOrderPromotionCommand command, CancellationToken cancellationToken)
        {
            Command = command;
            return Task.FromResult(new ProductionOrderPromotionResult(
                42, ProductionOrderPromotionOutcome.Created));
        }
    }

    private sealed class UnavailableStore : IProductionOrderPromotionStore
    {
        public Task<ProductionOrderPromotionResult> PromoteAsync(
            ProductionOrderPromotionCommand command, CancellationToken cancellationToken) =>
            throw new ProductionOrderPromotionUnavailableException("synthetic SQL detail");
    }
}
