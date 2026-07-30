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

public sealed class OperatorStopEndpointTests
{
    private static readonly Guid Correlation =
        Guid.Parse("701b2a0c-2b03-4a08-b58d-d0d12dd310fc");

    [Fact]
    public async Task PostOperatorStop_ReturnsCreatedContract()
    {
        using var factory = Factory(new StubStarter());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/12/operator-stops",
            new Request(7, "WC", Correlation));
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.Equal(31, body.RootElement.GetProperty("id").GetInt64());
        Assert.Equal(2, body.RootElement.GetProperty("activeResources").GetInt32());
    }

    [Theory]
    [InlineData(0, 7, "WC", "LINE_SESSION_ID_INVALID")]
    [InlineData(12, 0, "WC", "EMPLOYEE_ID_INVALID")]
    [InlineData(12, 7, "OTRO", "STOP_REASON_INVALID")]
    public async Task PostOperatorStop_ValidatesContract(
        long sessionId, long employeeId, string reason, string code)
    {
        using var factory = Factory(new StubStarter());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            $"/api/line-sessions/{sessionId}/operator-stops",
            new Request(employeeId, reason, Correlation));
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal(code, body.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task PostOperatorStop_HidesInfrastructureFailure()
    {
        using var factory = Factory(new UnavailableStarter());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/12/operator-stops",
            new Request(7, "WC", Correlation));
        var text = await response.Content.ReadAsStringAsync();
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.DoesNotContain("synthetic database detail", text);
    }

    [Fact]
    public async Task PostOperatorStop_ReturnsSafeConflict()
    {
        using var factory = Factory(new RejectingStarter());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/12/operator-stops",
            new Request(7, "WC", Correlation));
        var text = await response.Content.ReadAsStringAsync();
        using var body = JsonDocument.Parse(text);
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Equal(
            "OPERATOR_STOP_ALREADY_OPEN",
            body.RootElement.GetProperty("code").GetString());
        Assert.DoesNotContain("52211", text);
    }

    private static WebApplicationFactory<Program> Factory(IOperatorStopStarter starter) =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IOperatorStopStarter>();
                services.AddSingleton(starter);
            }));

    private sealed record Request(long EmployeeId, string Reason, Guid CorrelationId);
    private sealed class StubStarter : IOperatorStopStarter
    {
        public Task<OperatorStopRecord> StartAsync(
            StartOperatorStopCommand command, CancellationToken cancellationToken) =>
            Task.FromResult(new OperatorStopRecord(31, 2));
    }
    private sealed class UnavailableStarter : IOperatorStopStarter
    {
        public Task<OperatorStopRecord> StartAsync(
            StartOperatorStopCommand command, CancellationToken cancellationToken) =>
            throw new LineSessionUnavailableException("synthetic database detail");
    }
    private sealed class RejectingStarter : IOperatorStopStarter
    {
        public Task<OperatorStopRecord> StartAsync(
            StartOperatorStopCommand command, CancellationToken cancellationToken) =>
            throw new LineSessionRejectedException(
                "OPERATOR_STOP_ALREADY_OPEN",
                "El fichaje ya tiene un paro abierto.");
    }
}
