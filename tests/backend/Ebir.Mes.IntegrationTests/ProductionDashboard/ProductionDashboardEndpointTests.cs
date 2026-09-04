using System.Net;
using System.Text.Json;
using Ebir.Mes.Application.ProductionDashboard;
using Ebir.Mes.Application.ProductionOrders;
using Ebir.Mes.Application.ProductionWorkstations;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Xunit;

namespace Ebir.Mes.IntegrationTests.ProductionDashboard;

public sealed class ProductionDashboardEndpointTests
{
    [Fact]
    public async Task Dashboard_ReturnsActiveAndFreeLinesInOneSnapshot()
    {
        var now = new DateTime(2026, 9, 4, 10, 0, 0, DateTimeKind.Utc);
        var order = new ProductionOrderSelectionRecord(
            36, "FL26-00008", "27920LG", "Producto piloto", "LOTE-08",
            100, 60, 20, 0, 10m, "ABIERTA", now.AddHours(-1));
        var table = new ProductionTableStateRecord(
            40, 36, 1, "PRODUCIENDO", now.AddMinutes(-30), now, 1800, 2,
            12m, "POK", 20,
            [new(7, "EMP-7", "Operario piloto", now.AddMinutes(-30), 1800, "PRODUCIENDO")]);
        var snapshot = new ProductionDashboardSnapshotRecord(now,
        [
            new(1, "LINEA-01", "Linea uno", "CT-01", "Fabricacion",
                "PRODUCIENDO", null, now, order, table, 3,
                "CONFIRMADA", "IMPRESA", 0, 0, 0, 0),
            new(2, "LINEA-02", "Linea dos", "CT-01", "Fabricacion",
                "LIBRE", null, now, null, null, 0,
                null, null, 0, 0, 0, 0)
        ]);
        using var factory = CreateFactory(new StubReader(snapshot));
        using var client = factory.CreateClient();

        using var response = await client.GetAsync("/api/production-dashboard");
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(now, body.RootElement.GetProperty("serverTimeUtc").GetDateTime());
        var lines = body.RootElement.GetProperty("lines").EnumerateArray().ToArray();
        Assert.Equal(2, lines.Length);
        Assert.Equal("FL26-00008", lines[0].GetProperty("order")
            .GetProperty("orderNumber").GetString());
        Assert.Equal(60, lines[0].GetProperty("order")
            .GetProperty("goodQuantity").GetInt32());
        Assert.Single(lines[0].GetProperty("table")
            .GetProperty("operators").EnumerateArray());
        Assert.Equal(JsonValueKind.Null, lines[1].GetProperty("order").ValueKind);
    }

    [Fact]
    public async Task Dashboard_HidesInfrastructureFailure()
    {
        using var factory = CreateFactory(new UnavailableReader());
        using var client = factory.CreateClient();

        using var response = await client.GetAsync("/api/production-dashboard");
        var text = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.Contains("PRODUCTION_DASHBOARD_UNAVAILABLE", text);
        Assert.DoesNotContain("synthetic database detail", text);
    }

    private static WebApplicationFactory<Program> CreateFactory(IProductionDashboardReader reader) =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IProductionDashboardReader>();
                services.AddSingleton(reader);
            }));

    private sealed class StubReader(ProductionDashboardSnapshotRecord snapshot)
        : IProductionDashboardReader
    {
        public Task<ProductionDashboardSnapshotRecord> ReadAsync(
            CancellationToken cancellationToken) => Task.FromResult(snapshot);
    }

    private sealed class UnavailableReader : IProductionDashboardReader
    {
        public Task<ProductionDashboardSnapshotRecord> ReadAsync(
            CancellationToken cancellationToken) =>
            throw new ProductionDashboardUnavailableException("synthetic database detail");
    }
}
