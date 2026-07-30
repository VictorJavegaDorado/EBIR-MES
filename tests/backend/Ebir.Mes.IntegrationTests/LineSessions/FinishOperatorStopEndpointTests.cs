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

public sealed class FinishOperatorStopEndpointTests
{
    private static readonly Guid Correlation = Guid.NewGuid();

    [Fact]
    public async Task PostFinishStop_ReturnsSafeContract()
    {
        using var factory = Factory(new StubFinisher());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/12/operator-stops/finish",
            new Request(7, Correlation));
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(31, body.RootElement.GetProperty("id").GetInt64());
        Assert.Equal(44, body.RootElement.GetProperty("finishedSubstitutionId").GetInt64());
        Assert.Equal(3, body.RootElement.GetProperty("activeResources").GetInt32());
    }

    [Fact]
    public async Task PostFinishStop_HidesInfrastructureFailure()
    {
        using var factory = Factory(new UnavailableFinisher());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/12/operator-stops/finish",
            new Request(7, Correlation));
        var text = await response.Content.ReadAsStringAsync();
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.DoesNotContain("synthetic database detail", text);
    }

    private static WebApplicationFactory<Program> Factory(IOperatorStopFinisher finisher) =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IOperatorStopFinisher>();
                services.AddSingleton(finisher);
            }));
    private sealed record Request(long EmployeeId, Guid CorrelationId);
    private sealed class StubFinisher : IOperatorStopFinisher
    {
        public Task<FinishedOperatorStopRecord> FinishAsync(
            FinishOperatorStopCommand command, CancellationToken cancellationToken) =>
            Task.FromResult(new FinishedOperatorStopRecord(31, 44, 3));
    }
    private sealed class UnavailableFinisher : IOperatorStopFinisher
    {
        public Task<FinishedOperatorStopRecord> FinishAsync(
            FinishOperatorStopCommand command, CancellationToken cancellationToken) =>
            throw new LineSessionUnavailableException("synthetic database detail");
    }
}
