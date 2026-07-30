using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Ebir.Mes.Application.Replenishment;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Xunit;

namespace Ebir.Mes.IntegrationTests.Replenishment;

public sealed class CreateReplenishmentRequestEndpointTests
{
    private static readonly Guid Correlation = Guid.NewGuid();

    [Fact]
    public async Task PostRequest_ReturnsCreatedContract()
    {
        using var factory = Factory(new StubCreator());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/12/replenishment-requests",
            new Request(25, 4, 7, 31, Correlation));
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.Equal(41, body.RootElement.GetProperty("id").GetInt64());
        Assert.Equal("PENDIENTE", body.RootElement.GetProperty("state").GetString());
        Assert.Equal(31, body.RootElement.GetProperty("scrapId").GetInt64());
        Assert.Equal(Correlation,
            body.RootElement.GetProperty("correlationId").GetGuid());
    }

    [Fact]
    public async Task PostRequest_ReturnsBadRequest()
    {
        using var factory = Factory(new StubCreator());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/0/replenishment-requests",
            new Request(25, 4, 7, null, Correlation));
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("LINE_SESSION_ID_INVALID",
            body.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task PostRequest_ReturnsSafeConflict()
    {
        using var factory = Factory(new RejectingCreator());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/12/replenishment-requests",
            new Request(25, 4, 7, 31, Correlation));
        var text = await response.Content.ReadAsStringAsync();
        using var body = JsonDocument.Parse(text);
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Equal("LINKED_SCRAP_CANCELLED",
            body.RootElement.GetProperty("code").GetString());
        Assert.DoesNotContain("55215", text);
    }

    [Fact]
    public async Task PostRequest_HidesInfrastructureFailure()
    {
        using var factory = Factory(new UnavailableCreator());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/12/replenishment-requests",
            new Request(25, 4, 7, null, Correlation));
        var text = await response.Content.ReadAsStringAsync();
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.DoesNotContain("synthetic database detail", text);
    }

    private static WebApplicationFactory<Program> Factory(
        IReplenishmentRequestCreator creator) =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IReplenishmentRequestCreator>();
                services.AddSingleton(creator);
            }));

    private sealed record Request(
        long OrderComponentId,
        int RequestedQuantity,
        long RequestedByEmployeeId,
        long? ScrapId,
        Guid CorrelationId);

    private sealed class StubCreator : IReplenishmentRequestCreator
    {
        public Task<long> CreateAsync(
            CreateReplenishmentRequestCommand command,
            CancellationToken cancellationToken) => Task.FromResult(41L);
    }

    private sealed class RejectingCreator : IReplenishmentRequestCreator
    {
        public Task<long> CreateAsync(
            CreateReplenishmentRequestCommand command,
            CancellationToken cancellationToken) =>
            throw new ReplenishmentRejectedException(
                "LINKED_SCRAP_CANCELLED",
                "El scrap vinculado está anulado.");
    }

    private sealed class UnavailableCreator : IReplenishmentRequestCreator
    {
        public Task<long> CreateAsync(
            CreateReplenishmentRequestCommand command,
            CancellationToken cancellationToken) =>
            throw new ReplenishmentUnavailableException("synthetic database detail");
    }
}
