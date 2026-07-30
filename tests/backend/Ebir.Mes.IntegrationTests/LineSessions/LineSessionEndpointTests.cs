using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Ebir.Mes.Application.LineSessions;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Xunit;

namespace Ebir.Mes.IntegrationTests.LineSessions;

public sealed class LineSessionEndpointTests
{
    private static readonly Guid CorrelationId =
        Guid.Parse("abfc2bb6-2418-47fb-98a6-76966c61b1fb");

    [Fact]
    public async Task PostLineSession_ReturnsCreatedContract()
    {
        using var factory = CreateFactory(new StubOpener(73));
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync("/api/line-sessions", ValidRequest());
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.Equal("/api/line-sessions/73", response.Headers.Location?.OriginalString);
        Assert.Equal(73, body.RootElement.GetProperty("id").GetInt64());
        Assert.Equal(
            CorrelationId,
            body.RootElement.GetProperty("correlationId").GetGuid());
    }

    [Fact]
    public async Task PostLineSession_ReturnsBadRequestForInvalidIdentifier()
    {
        using var factory = CreateFactory(new StubOpener(73));
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions", ValidRequest() with { LineId = 0 });
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("LINE_ID_INVALID", body.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task PostLineSession_ReturnsBadRequestForEmptyCorrelationId()
    {
        using var factory = CreateFactory(new StubOpener(73));
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions", ValidRequest() with { CorrelationId = Guid.Empty });
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal(
            "CORRELATION_ID_INVALID",
            body.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task PostLineSession_ReturnsConflictWithSafeRejection()
    {
        using var factory = CreateFactory(new RejectingOpener());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions", ValidRequest());
        var text = await response.Content.ReadAsStringAsync();
        using var body = JsonDocument.Parse(text);
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Equal("LINE_NOT_AVAILABLE", body.RootElement.GetProperty("code").GetString());
        Assert.DoesNotContain("51705", text);
    }

    [Fact]
    public async Task PostLineSession_HidesInfrastructureFailure()
    {
        using var factory = CreateFactory(new UnavailableOpener());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions", ValidRequest());
        var text = await response.Content.ReadAsStringAsync();
        using var body = JsonDocument.Parse(text);
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.Equal(
            "LINE_SESSION_UNAVAILABLE",
            body.RootElement.GetProperty("code").GetString());
        Assert.DoesNotContain("synthetic database detail", text);
    }

    private static OpenLineSessionRequest ValidRequest() =>
        new(1, 2, 3, 4, false, CorrelationId);

    private static WebApplicationFactory<Program> CreateFactory(ILineSessionOpener opener) =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<ILineSessionOpener>();
                services.AddSingleton(opener);
            }));

    private sealed record OpenLineSessionRequest(
        long OrderId, long LineId, long PalletFormatOrderId, long SupervisorId,
        bool OutsideScheduleConfirmed, Guid CorrelationId);

    private sealed class StubOpener(long id) : ILineSessionOpener
    {
        public Task<long> OpenAsync(
            OpenLineSessionCommand command, CancellationToken cancellationToken) =>
            Task.FromResult(id);
    }

    private sealed class RejectingOpener : ILineSessionOpener
    {
        public Task<long> OpenAsync(
            OpenLineSessionCommand command, CancellationToken cancellationToken) =>
            throw new LineSessionRejectedException(
                "LINE_NOT_AVAILABLE",
                "La línea no está libre para abrir una sesión.");
    }

    private sealed class UnavailableOpener : ILineSessionOpener
    {
        public Task<long> OpenAsync(
            OpenLineSessionCommand command, CancellationToken cancellationToken) =>
            throw new LineSessionUnavailableException("synthetic database detail");
    }
}
