using System.Net;
using System.Text.Json;
using Ebir.Mes.Application.Printing.LabelControl;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Xunit;

namespace Ebir.Mes.IntegrationTests.Printing;

public sealed class LabelControlEndpointTests
{
    [Fact]
    public async Task Control_ReturnsOrdersPalletsAndSafeReprintState()
    {
        var now = new DateTime(2026, 9, 9, 8, 0, 0, DateTimeKind.Utc);
        var snapshot = new LabelControlSnapshotRecord(now,
        [
            new(42, "FL26-00015", "27920LG", "Producto piloto", "ABIERTA",
                40, "LINEA-TEST-01", "Linea piloto", now.AddMinutes(-5),
            [
                new(58, 1, 20, false, now.AddMinutes(-5), 69, "CONFIRMADA",
                    60, "IMPRESA", 75, "COMPLETADO", 1, true, true)
            ])
        ]);
        using var factory = CreateFactory(new StubReader(snapshot));
        using var client = factory.CreateClient();

        using var response = await client.GetAsync("/api/label-control");
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var order = Assert.Single(body.RootElement.GetProperty("orders").EnumerateArray());
        Assert.Equal("FL26-00015", order.GetProperty("orderNumber").GetString());
        var pallet = Assert.Single(order.GetProperty("pallets").EnumerateArray());
        Assert.True(pallet.GetProperty("hasIncident").GetBoolean());
        Assert.True(pallet.GetProperty("canReprint").GetBoolean());
        Assert.Equal("IMPRESA", pallet.GetProperty("labelState").GetString());
    }

    [Fact]
    public async Task Control_HidesInfrastructureFailure()
    {
        using var factory = CreateFactory(new UnavailableReader());
        using var client = factory.CreateClient();

        using var response = await client.GetAsync("/api/label-control");
        var text = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.Contains("LABEL_CONTROL_UNAVAILABLE", text);
        Assert.DoesNotContain("synthetic database detail", text);
    }

    private static WebApplicationFactory<Program> CreateFactory(ILabelControlReader reader) =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<ILabelControlReader>();
                services.AddSingleton(reader);
            }));

    private sealed class StubReader(LabelControlSnapshotRecord snapshot) : ILabelControlReader
    {
        public Task<LabelControlSnapshotRecord> ReadAsync(
            CancellationToken cancellationToken) => Task.FromResult(snapshot);
    }

    private sealed class UnavailableReader : ILabelControlReader
    {
        public Task<LabelControlSnapshotRecord> ReadAsync(
            CancellationToken cancellationToken) =>
            throw new LabelControlUnavailableException("synthetic database detail");
    }
}
