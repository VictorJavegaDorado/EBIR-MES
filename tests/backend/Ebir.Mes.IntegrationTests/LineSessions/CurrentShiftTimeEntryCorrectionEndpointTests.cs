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

public sealed class CurrentShiftTimeEntryCorrectionEndpointTests
{
    private static readonly Guid Correlation = Guid.NewGuid();
    private static readonly DateTimeOffset Entry =
        new(2026, 7, 30, 6, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task PostCorrection_ReturnsSafeContract()
    {
        using var factory = Factory(new StubCorrector());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/time-entries/44/corrections",
            new Request(Entry, null, 9, "Ajuste", Correlation));
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(44, body.RootElement.GetProperty("id").GetInt64());
        Assert.Equal(Correlation,
            body.RootElement.GetProperty("correlationId").GetGuid());
    }

    [Fact]
    public async Task PostCorrection_ReturnsBadRequest()
    {
        using var factory = Factory(new StubCorrector());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/time-entries/0/corrections",
            new Request(Entry, null, 9, "Ajuste", Correlation));
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("TIME_ENTRY_ID_INVALID",
            body.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task PostCorrection_ReturnsSafeConflict()
    {
        using var factory = Factory(new RejectingCorrector());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/time-entries/44/corrections",
            new Request(Entry, null, 9, "Ajuste", Correlation));
        var text = await response.Content.ReadAsStringAsync();
        using var body = JsonDocument.Parse(text);
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Equal("TIME_ENTRY_INTERVAL_OVERLAP",
            body.RootElement.GetProperty("code").GetString());
        Assert.DoesNotContain("52616", text);
    }

    [Fact]
    public async Task PostCorrection_HidesInfrastructureFailure()
    {
        using var factory = Factory(new UnavailableCorrector());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/time-entries/44/corrections",
            new Request(Entry, null, 9, "Ajuste", Correlation));
        var text = await response.Content.ReadAsStringAsync();
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.DoesNotContain("synthetic database detail", text);
    }

    private static WebApplicationFactory<Program> Factory(
        ICurrentShiftTimeEntryCorrector corrector) =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<ICurrentShiftTimeEntryCorrector>();
                services.AddSingleton(corrector);
            }));

    private sealed record Request(
        DateTimeOffset CorrectedEntryUtc,
        DateTimeOffset? CorrectedExitUtc,
        long SupervisorId,
        string Reason,
        Guid CorrelationId);

    private sealed class StubCorrector : ICurrentShiftTimeEntryCorrector
    {
        public Task CorrectAsync(
            CorrectCurrentShiftTimeEntryCommand command,
            CancellationToken cancellationToken) => Task.CompletedTask;
    }

    private sealed class RejectingCorrector : ICurrentShiftTimeEntryCorrector
    {
        public Task CorrectAsync(
            CorrectCurrentShiftTimeEntryCommand command,
            CancellationToken cancellationToken) =>
            throw new LineSessionRejectedException(
                "TIME_ENTRY_INTERVAL_OVERLAP",
                "El intervalo corregido solapa otro fichaje.");
    }

    private sealed class UnavailableCorrector : ICurrentShiftTimeEntryCorrector
    {
        public Task CorrectAsync(
            CorrectCurrentShiftTimeEntryCommand command,
            CancellationToken cancellationToken) =>
            throw new LineSessionUnavailableException("synthetic database detail");
    }
}
