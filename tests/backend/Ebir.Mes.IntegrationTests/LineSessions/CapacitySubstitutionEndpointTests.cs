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

public sealed class CapacitySubstitutionEndpointTests
{
    private static readonly Guid Correlation = Guid.NewGuid();

    [Fact]
    public async Task PostSubstitution_ReturnsCreatedContract()
    {
        using var factory = Factory(new StubStarter());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/12/capacity-substitutions",
            new Request(7, 9, "Cobertura", Correlation));
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.Equal(31, body.RootElement.GetProperty("id").GetInt64());
        Assert.Equal(44, body.RootElement.GetProperty("supervisorTimeEntryId").GetInt64());
        Assert.Equal(3, body.RootElement.GetProperty("activeResources").GetInt32());
    }

    [Fact]
    public async Task PostSubstitution_ReturnsSafeConflict()
    {
        using var factory = Factory(new RejectingStarter());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/12/capacity-substitutions",
            new Request(7, 9, "Cobertura", Correlation));
        var text = await response.Content.ReadAsStringAsync();
        using var body = JsonDocument.Parse(text);
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Equal("REPLACED_OPERATOR_STOP_NOT_OPEN",
            body.RootElement.GetProperty("code").GetString());
        Assert.DoesNotContain("52414", text);
    }

    private static WebApplicationFactory<Program> Factory(
        ICapacitySubstitutionStarter starter) =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<ICapacitySubstitutionStarter>();
                services.AddSingleton(starter);
            }));
    private sealed record Request(
        long ReplacedOperatorId, long SubstituteSupervisorId,
        string Reason, Guid CorrelationId);
    private sealed class StubStarter : ICapacitySubstitutionStarter
    {
        public Task<CapacitySubstitutionRecord> StartAsync(
            StartCapacitySubstitutionCommand command,
            CancellationToken cancellationToken) =>
            Task.FromResult(new CapacitySubstitutionRecord(31, 44, 3));
    }
    private sealed class RejectingStarter : ICapacitySubstitutionStarter
    {
        public Task<CapacitySubstitutionRecord> StartAsync(
            StartCapacitySubstitutionCommand command,
            CancellationToken cancellationToken) =>
            throw new LineSessionRejectedException(
                "REPLACED_OPERATOR_STOP_NOT_OPEN",
                "La sustitución requiere un paro abierto.");
    }
}
