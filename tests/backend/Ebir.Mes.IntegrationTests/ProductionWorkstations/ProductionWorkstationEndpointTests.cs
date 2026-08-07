using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Ebir.Mes.Application.ProductionOrders;
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
    public async Task Active_RecoversTheLineTableEvenWhenTheOrderIsNoLongerSelectable()
    {
        var now = new DateTime(2026, 8, 7, 8, 20, 0, DateTimeKind.Utc);
        var state = new ProductionTableStateRecord(
            12, 28, 40, "PRODUCIENDO", now.AddMinutes(-10), now,
            600, 1, 6m, "POK", 20,
            [new(3, "EMP-3", "Operario piloto", now.AddMinutes(-10), 600, "PRODUCIENDO")]);
        var order = new ProductionOrderSelectionRecord(
            28, "FL26-00003", "27924LG", "Producto piloto", "", 100,
            100, 0, 0, 10m, "PENDIENTE_CIERRE", now.AddDays(-1));
        using var factory = CreateFactory(
            new StubStarter(new(12, 31, null, false)),
            new StubStateReader(state, new(order, state)));
        using var client = factory.CreateClient();

        using var response = await client.GetAsync(
            "/api/production-workstations/active?lineId=40");
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("FL26-00003", body.RootElement.GetProperty("order")
            .GetProperty("orderNumber").GetString());
        Assert.Equal("PENDIENTE_CIERRE", body.RootElement.GetProperty("order")
            .GetProperty("state").GetString());
        Assert.Single(body.RootElement.GetProperty("table")
            .GetProperty("operators").EnumerateArray());
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

    [Fact]
    public async Task CompleteOrder_ReturnsFinalizedAfterTheServerAcceptsTheTransition()
    {
        var completer = new StubCompleter();
        using var factory = CreateFactory(
            new StubStarter(new(12, 31, null, false)),
            new StubStateReader(null),
            completer);
        using var client = factory.CreateClient();

        using var response = await client.PostAsJsonAsync(
            "/api/production-workstations/12/complete-order",
            new { correlationId = CorrelationId });
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("FINALIZADA", body.RootElement.GetProperty("state").GetString());
        Assert.Equal(12, completer.LastCommand?.LineSessionId);
        Assert.Equal(CorrelationId, completer.LastCommand?.CorrelationId);
    }

    [Fact]
    public async Task CompleteOrder_ReturnsSafeConflict()
    {
        using var factory = CreateFactory(
            new StubStarter(new(12, 31, null, false)),
            new StubStateReader(null),
            new RejectingCompleter());
        using var client = factory.CreateClient();

        using var response = await client.PostAsJsonAsync(
            "/api/production-workstations/12/complete-order",
            new { correlationId = CorrelationId });
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Equal(
            "PALLET_OUTPUT_NOT_CONFIRMED",
            body.RootElement.GetProperty("code").GetString());
    }

    private static WebApplicationFactory<Program> CreateFactory(
        IProductionTableStarter starter,
        IProductionTableStateReader reader,
        IProductionOrderCompleter? completer = null) =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IProductionTableStarter>();
                services.RemoveAll<IProductionTableStateReader>();
                services.RemoveAll<IProductionOrderCompleter>();
                services.AddSingleton(starter);
                services.AddSingleton(reader);
                services.AddSingleton(completer ?? new StubCompleter());
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

    private sealed class StubStateReader(
        ProductionTableStateRecord? state,
        ActiveProductionTableRecord? active = null)
        : IProductionTableStateReader
    {
        public Task<ProductionTableStateRecord?> ReadAsync(
            long orderId,
            long lineId,
            CancellationToken cancellationToken) => Task.FromResult(state);

        public Task<ActiveProductionTableRecord?> ReadActiveByLineAsync(
            long lineId,
            CancellationToken cancellationToken) => Task.FromResult(active);
    }

    private sealed class StubCompleter : IProductionOrderCompleter
    {
        public CompleteProductionOrderCommand? LastCommand { get; private set; }

        public Task CompleteAsync(
            CompleteProductionOrderCommand command,
            CancellationToken cancellationToken)
        {
            LastCommand = command;
            return Task.CompletedTask;
        }
    }

    private sealed class RejectingCompleter : IProductionOrderCompleter
    {
        public Task CompleteAsync(
            CompleteProductionOrderCommand command,
            CancellationToken cancellationToken) =>
            throw new ProductionTableRejectedException(
                "PALLET_OUTPUT_NOT_CONFIRMED",
                "Las salidas todavía no están confirmadas.");
    }
}
