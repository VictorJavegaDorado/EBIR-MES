using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Ebir.Mes.Application.ProductionWorkstations;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Xunit;

namespace Ebir.Mes.IntegrationTests.ProductionWorkstations;

public sealed class ProductionWorkstationEndpointTests
{
    private static readonly Guid CorrelationId =
        Guid.Parse("9a8b1e15-ec9a-46e5-9f3e-c159b069080b");

    [Fact]
    public async Task StartOrJoin_ReturnsTheAtomicResult()
    {
        using var factory = CreateFactory(
            new StubStarter(new(12, 31, 47, true)),
            new StubStateReader(null));
        using var client = factory.CreateClient();

        using var response = await client.PostAsJsonAsync(
            "/api/production-workstations/start-or-join",
            new { orderId = 1, lineId = 2, employeeId = 3, correlationId = CorrelationId });
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(12, body.RootElement.GetProperty("lineSessionId").GetInt64());
        Assert.Equal(31, body.RootElement.GetProperty("timeEntryId").GetInt64());
        Assert.Equal(47, body.RootElement.GetProperty("palletReservationId").GetInt64());
        Assert.True(body.RootElement.GetProperty("sessionCreated").GetBoolean());
        Assert.Equal(CorrelationId, body.RootElement.GetProperty("correlationId").GetGuid());
    }

    [Fact]
    public async Task State_ReturnsPersistedTimersAndOperators()
    {
        var now = new DateTime(2026, 8, 5, 10, 20, 0, DateTimeKind.Utc);
        var state = new ProductionTableStateRecord(
            12, 1, 2, "PRODUCIENDO", now.AddMinutes(-5), now,
            300, 1, 6m, "POK", 20,
            [new(3, "EMP-3", "Operario piloto", now.AddMinutes(-5), 300, "PRODUCIENDO")]);
        using var factory = CreateFactory(
            new StubStarter(new(12, 31, null, false)),
            new StubStateReader(state));
        using var client = factory.CreateClient();

        using var response = await client.GetAsync(
            "/api/production-workstations/state?orderId=1&lineId=2");
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("PRODUCIENDO", body.RootElement.GetProperty("state").GetString());
        Assert.Equal(300, body.RootElement.GetProperty("productiveSeconds").GetInt64());
        Assert.Single(body.RootElement.GetProperty("operators").EnumerateArray());
    }

    [Fact]
    public async Task State_ReturnsNotFoundBeforeTheFirstOperator()
    {
        using var factory = CreateFactory(
            new StubStarter(new(12, 31, null, false)),
            new StubStateReader(null));
        using var client = factory.CreateClient();

        using var response = await client.GetAsync(
            "/api/production-workstations/state?orderId=1&lineId=2");
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.Equal(
            "PRODUCTION_TABLE_NOT_ACTIVE",
            body.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task StartOrJoin_HidesInfrastructureFailure()
    {
        using var factory = CreateFactory(
            new UnavailableStarter(),
            new StubStateReader(null));
        using var client = factory.CreateClient();

        using var response = await client.PostAsJsonAsync(
            "/api/production-workstations/start-or-join",
            new { orderId = 1, lineId = 2, employeeId = 3, correlationId = CorrelationId });
        var text = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.DoesNotContain("synthetic database detail", text);
    }

    private static WebApplicationFactory<Program> CreateFactory(
        IProductionTableStarter starter,
        IProductionTableStateReader reader) =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IProductionTableStarter>();
                services.RemoveAll<IProductionTableStateReader>();
                services.AddSingleton(starter);
                services.AddSingleton(reader);
            }));

    private sealed class StubStarter(ProductionTableStartRecord result)
        : IProductionTableStarter
    {
        public Task<ProductionTableStartRecord> StartOrJoinAsync(
            StartOrJoinProductionTableCommand command,
            CancellationToken cancellationToken) => Task.FromResult(result);
    }

    private sealed class UnavailableStarter : IProductionTableStarter
    {
        public Task<ProductionTableStartRecord> StartOrJoinAsync(
            StartOrJoinProductionTableCommand command,
            CancellationToken cancellationToken) =>
            throw new ProductionTableUnavailableException("synthetic database detail");
    }

    private sealed class StubStateReader(ProductionTableStateRecord? state)
        : IProductionTableStateReader
    {
        public Task<ProductionTableStateRecord?> ReadAsync(
            long orderId,
            long lineId,
            CancellationToken cancellationToken) => Task.FromResult(state);
    }
}
