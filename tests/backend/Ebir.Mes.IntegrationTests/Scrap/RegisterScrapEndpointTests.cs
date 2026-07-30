using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Ebir.Mes.Application.Scrap;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Xunit;

namespace Ebir.Mes.IntegrationTests.Scrap;

public sealed class RegisterScrapEndpointTests
{
    private static readonly Guid Correlation = Guid.NewGuid();

    [Fact]
    public async Task PostScrap_ReturnsCreatedContract()
    {
        using var factory = Factory(new StubRegistrar());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/12/scrap",
            new Request(25, 3, 4, "Pieza dañada", 7, Correlation));
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.Equal(31, body.RootElement.GetProperty("id").GetInt64());
        Assert.Equal(44, body.RootElement.GetProperty("navOperationId").GetInt64());
        Assert.Equal(Correlation,
            body.RootElement.GetProperty("correlationId").GetGuid());
    }

    [Fact]
    public async Task PostScrap_ReturnsBadRequest()
    {
        using var factory = Factory(new StubRegistrar());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/0/scrap",
            new Request(25, 3, 4, null, 7, Correlation));
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("LINE_SESSION_ID_INVALID",
            body.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task PostScrap_ReturnsSafeConflict()
    {
        using var factory = Factory(new RejectingRegistrar());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/12/scrap",
            new Request(25, 3, 4, null, 7, Correlation));
        var text = await response.Content.ReadAsStringAsync();
        using var body = JsonDocument.Parse(text);
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Equal("ORDER_COMPONENT_NOT_FOUND",
            body.RootElement.GetProperty("code").GetString());
        Assert.DoesNotContain("55013", text);
    }

    [Fact]
    public async Task PostScrap_HidesInfrastructureFailure()
    {
        using var factory = Factory(new UnavailableRegistrar());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/12/scrap",
            new Request(25, 3, 4, null, 7, Correlation));
        var text = await response.Content.ReadAsStringAsync();
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.DoesNotContain("synthetic database detail", text);
    }

    private static WebApplicationFactory<Program> Factory(IScrapRegistrar registrar) =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IScrapRegistrar>();
                services.AddSingleton(registrar);
            }));

    private sealed record Request(
        long OrderComponentId,
        short ScrapReasonId,
        int Quantity,
        string? Description,
        long RegisteredByEmployeeId,
        Guid CorrelationId);

    private sealed class StubRegistrar : IScrapRegistrar
    {
        public Task<RegisteredScrapRecord> RegisterAsync(
            RegisterScrapCommand command,
            CancellationToken cancellationToken) =>
            Task.FromResult(new RegisteredScrapRecord(31, 44));
    }

    private sealed class RejectingRegistrar : IScrapRegistrar
    {
        public Task<RegisteredScrapRecord> RegisterAsync(
            RegisterScrapCommand command,
            CancellationToken cancellationToken) =>
            throw new ScrapRejectedException(
                "ORDER_COMPONENT_NOT_FOUND",
                "El componente no pertenece a la orden.");
    }

    private sealed class UnavailableRegistrar : IScrapRegistrar
    {
        public Task<RegisteredScrapRecord> RegisterAsync(
            RegisterScrapCommand command,
            CancellationToken cancellationToken) =>
            throw new ScrapUnavailableException("synthetic database detail");
    }
}
