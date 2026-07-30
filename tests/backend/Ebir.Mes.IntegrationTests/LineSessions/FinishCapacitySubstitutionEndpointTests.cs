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

public sealed class FinishCapacitySubstitutionEndpointTests
{
    private static readonly Guid Correlation = Guid.NewGuid();

    [Fact]
    public async Task PostFinishSubstitution_ReturnsSafeContract()
    {
        using var factory = Factory(new StubFinisher());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/capacity-substitutions/31/finish",
            new Request(9, "Fin de cobertura", Correlation));
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(31, body.RootElement.GetProperty("id").GetInt64());
        Assert.Equal(2, body.RootElement.GetProperty("activeResources").GetInt32());
        Assert.Equal(Correlation,
            body.RootElement.GetProperty("correlationId").GetGuid());
    }

    [Fact]
    public async Task PostFinishSubstitution_ReturnsBadRequest()
    {
        using var factory = Factory(new StubFinisher());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/capacity-substitutions/0/finish",
            new Request(9, "Fin de cobertura", Correlation));
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("CAPACITY_SUBSTITUTION_ID_INVALID",
            body.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task PostFinishSubstitution_ReturnsSafeConflict()
    {
        using var factory = Factory(new RejectingFinisher());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/capacity-substitutions/31/finish",
            new Request(9, "Fin de cobertura", Correlation));
        var text = await response.Content.ReadAsStringAsync();
        using var body = JsonDocument.Parse(text);
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Equal("CAPACITY_SUBSTITUTION_NOT_ACTIVE",
            body.RootElement.GetProperty("code").GetString());
        Assert.DoesNotContain("52514", text);
    }

    [Fact]
    public async Task PostFinishSubstitution_HidesInfrastructureFailure()
    {
        using var factory = Factory(new UnavailableFinisher());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/capacity-substitutions/31/finish",
            new Request(9, "Fin de cobertura", Correlation));
        var text = await response.Content.ReadAsStringAsync();
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.DoesNotContain("synthetic database detail", text);
    }

    private static WebApplicationFactory<Program> Factory(
        ICapacitySubstitutionFinisher finisher) =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<ICapacitySubstitutionFinisher>();
                services.AddSingleton(finisher);
            }));

    private sealed record Request(
        long SupervisorId, string Reason, Guid CorrelationId);

    private sealed class StubFinisher : ICapacitySubstitutionFinisher
    {
        public Task<int> FinishAsync(
            FinishCapacitySubstitutionCommand command,
            CancellationToken cancellationToken) => Task.FromResult(2);
    }

    private sealed class RejectingFinisher : ICapacitySubstitutionFinisher
    {
        public Task<int> FinishAsync(
            FinishCapacitySubstitutionCommand command,
            CancellationToken cancellationToken) =>
            throw new LineSessionRejectedException(
                "CAPACITY_SUBSTITUTION_NOT_ACTIVE",
                "La sustitución ya no está activa.");
    }

    private sealed class UnavailableFinisher : ICapacitySubstitutionFinisher
    {
        public Task<int> FinishAsync(
            FinishCapacitySubstitutionCommand command,
            CancellationToken cancellationToken) =>
            throw new LineSessionUnavailableException("synthetic database detail");
    }
}
