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

public sealed class TransitionReplenishmentRequestEndpointTests
{
    private static readonly Guid Correlation = Guid.NewGuid();

    [Fact]
    public async Task PostTransition_ReturnsSafeContract()
    {
        using var factory = Factory(new StubTransitioner());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/replenishment-requests/41/transitions",
            new Request("en_camino", 8, null, Correlation));
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(41, body.RootElement.GetProperty("id").GetInt64());
        Assert.Equal("EN_CAMINO", body.RootElement.GetProperty("state").GetString());
        Assert.Equal(Correlation,
            body.RootElement.GetProperty("correlationId").GetGuid());
    }

    [Fact]
    public async Task PostTransition_ReturnsBadRequest()
    {
        using var factory = Factory(new StubTransitioner());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/replenishment-requests/41/transitions",
            new Request("RECHAZADA", 8, null, Correlation));
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("REPLENISHMENT_TRANSITION_COMMENT_REQUIRED",
            body.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task PostTransition_ReturnsSafeConflict()
    {
        using var factory = Factory(new RejectingTransitioner());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/replenishment-requests/41/transitions",
            new Request("ENTREGADA", 8, null, Correlation));
        var text = await response.Content.ReadAsStringAsync();
        using var body = JsonDocument.Parse(text);
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Equal("REPLENISHMENT_REQUEST_ASSIGNEE_MISMATCH",
            body.RootElement.GetProperty("code").GetString());
        Assert.DoesNotContain("55310", text);
    }

    [Fact]
    public async Task PostTransition_HidesInfrastructureFailure()
    {
        using var factory = Factory(new UnavailableTransitioner());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/replenishment-requests/41/transitions",
            new Request("ACEPTADA", 8, null, Correlation));
        var text = await response.Content.ReadAsStringAsync();
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.DoesNotContain("synthetic database detail", text);
    }

    private static WebApplicationFactory<Program> Factory(
        IReplenishmentRequestTransitioner transitioner) =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IReplenishmentRequestTransitioner>();
                services.AddSingleton(transitioner);
            }));

    private sealed record Request(
        string NewState,
        long EmployeeId,
        string? Comment,
        Guid CorrelationId);

    private sealed class StubTransitioner : IReplenishmentRequestTransitioner
    {
        public Task TransitionAsync(
            TransitionReplenishmentRequestCommand command,
            CancellationToken cancellationToken) => Task.CompletedTask;
    }

    private sealed class RejectingTransitioner
        : IReplenishmentRequestTransitioner
    {
        public Task TransitionAsync(
            TransitionReplenishmentRequestCommand command,
            CancellationToken cancellationToken) =>
            throw new ReplenishmentRejectedException(
                "REPLENISHMENT_REQUEST_ASSIGNEE_MISMATCH",
                "La solicitud pertenece a otro aprovisionador.");
    }

    private sealed class UnavailableTransitioner
        : IReplenishmentRequestTransitioner
    {
        public Task TransitionAsync(
            TransitionReplenishmentRequestCommand command,
            CancellationToken cancellationToken) =>
            throw new ReplenishmentUnavailableException("synthetic database detail");
    }
}
