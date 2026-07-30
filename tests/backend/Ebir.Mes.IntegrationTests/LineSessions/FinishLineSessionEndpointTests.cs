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

public sealed class FinishLineSessionEndpointTests
{
    private static readonly Guid CorrelationId =
        Guid.Parse("9cbb9ac1-166b-4c90-a201-d590431e8a27");

    [Fact]
    public async Task PostFinishShift_ReturnsClosedTimeEntries()
    {
        using var factory = CreateFactory(new StubFinisher(3));
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/12/finish-shift", new Request(7, CorrelationId));
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(3, body.RootElement.GetProperty("closedTimeEntries").GetInt32());
        Assert.Equal(CorrelationId, body.RootElement.GetProperty("correlationId").GetGuid());
    }

    [Theory]
    [InlineData(0, 7, "9cbb9ac1-166b-4c90-a201-d590431e8a27", "LINE_SESSION_ID_INVALID")]
    [InlineData(12, 0, "9cbb9ac1-166b-4c90-a201-d590431e8a27", "SUPERVISOR_ID_INVALID")]
    [InlineData(12, 7, "00000000-0000-0000-0000-000000000000", "CORRELATION_ID_INVALID")]
    public async Task PostFinishShift_ValidatesContract(
        long sessionId, long supervisorId, string correlation, string code)
    {
        using var factory = CreateFactory(new StubFinisher(0));
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            $"/api/line-sessions/{sessionId}/finish-shift",
            new Request(supervisorId, Guid.Parse(correlation)));
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal(code, body.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task PostFinishShift_HidesInfrastructureFailure()
    {
        using var factory = CreateFactory(new UnavailableFinisher());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/12/finish-shift", new Request(7, CorrelationId));
        var text = await response.Content.ReadAsStringAsync();
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.DoesNotContain("synthetic database detail", text);
    }

    private static WebApplicationFactory<Program> CreateFactory(
        ILineSessionFinisher finisher) =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<ILineSessionFinisher>();
                services.AddSingleton(finisher);
            }));

    private sealed record Request(long SupervisorId, Guid CorrelationId);
    private sealed class StubFinisher(int closed) : ILineSessionFinisher
    {
        public Task<int> FinishAsync(
            FinishLineSessionCommand command, CancellationToken cancellationToken) =>
            Task.FromResult(closed);
    }
    private sealed class UnavailableFinisher : ILineSessionFinisher
    {
        public Task<int> FinishAsync(
            FinishLineSessionCommand command, CancellationToken cancellationToken) =>
            throw new LineSessionUnavailableException("synthetic database detail");
    }
}
