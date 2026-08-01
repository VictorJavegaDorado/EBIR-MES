using System.Net;
using System.Text.Json;
using Ebir.Mes.Application.ProductionOrders;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Xunit;

namespace Ebir.Mes.IntegrationTests.ProductionOrders;

public sealed class ProductionOrderSelectionEndpointTests
{
    [Fact]
    public async Task ListAsync_returns_selectable_orders()
    {
        using var factory = Factory(new StubReader());
        using var response = await factory.CreateClient().GetAsync(
            "/api/production-orders");
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var order = Assert.Single(body.RootElement.EnumerateArray());
        Assert.Equal(28, order.GetProperty("productionOrderId").GetInt64());
        Assert.Equal("FL20-02277", order.GetProperty("orderNumber").GetString());
        Assert.Equal("FL2002277", order.GetProperty("lotNumber").GetString());
        Assert.Equal(36m, order.GetProperty("runTimeMinutes").GetDecimal());
    }

    [Fact]
    public async Task ListAsync_hides_reader_failure()
    {
        using var factory = Factory(new UnavailableReader());
        using var response = await factory.CreateClient().GetAsync(
            "/api/production-orders");
        var content = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.Contains("PRODUCTION_ORDER_SELECTION_UNAVAILABLE", content);
        Assert.DoesNotContain("synthetic SQL detail", content);
    }

    private static WebApplicationFactory<Program> Factory(
        IProductionOrderSelectionReader reader) =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment("Testing");
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IProductionOrderSelectionReader>();
                services.AddSingleton(reader);
            });
        });

    private sealed class StubReader : IProductionOrderSelectionReader
    {
        public Task<IReadOnlyList<ProductionOrderSelectionRecord>> ReadAsync(
            CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<ProductionOrderSelectionRecord>>
            ([new(28, "FL20-02277", "27979CI", "ESPEJO", "FL2002277",
                10, 0, 0, 0, 36m, "IMPORTADA", DateTime.UtcNow)]);
    }

    private sealed class UnavailableReader : IProductionOrderSelectionReader
    {
        public Task<IReadOnlyList<ProductionOrderSelectionRecord>> ReadAsync(
            CancellationToken cancellationToken) =>
            throw new ProductionOrderSelectionUnavailableException(
                "synthetic SQL detail");
    }
}
