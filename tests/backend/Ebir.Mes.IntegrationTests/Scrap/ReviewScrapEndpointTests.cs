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

public sealed class ReviewScrapEndpointTests
{
    private static readonly Guid Correlation = Guid.NewGuid();

    [Fact]
    public async Task PostRevision_ReturnsCreatedContract()
    {
        using var factory = Factory(new StubReviewer());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/scrap/31/revisions",
            CreateRequest(false, 2));
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.Equal(41, body.RootElement.GetProperty("id").GetInt64());
        Assert.Equal(31, body.RootElement.GetProperty("scrapId").GetInt64());
        Assert.Equal(44, body.RootElement.GetProperty("navOperationId").GetInt64());
        Assert.False(body.RootElement.GetProperty("isCancellation").GetBoolean());
    }

    [Fact]
    public async Task PostRevision_ReturnsBadRequest()
    {
        using var factory = Factory(new StubReviewer());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/scrap/0/revisions",
            CreateRequest(false, 2));
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("SCRAP_ID_INVALID",
            body.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task PostRevision_ReturnsSafeConflict()
    {
        using var factory = Factory(new RejectingReviewer());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/scrap/31/revisions",
            CreateRequest(false, 2));
        var text = await response.Content.ReadAsStringAsync();
        using var body = JsonDocument.Parse(text);
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Equal("SCRAP_NAV_RESULT_PENDING_OR_UNKNOWN",
            body.RootElement.GetProperty("code").GetString());
        Assert.DoesNotContain("55119", text);
    }

    [Fact]
    public async Task PostRevision_HidesInfrastructureFailure()
    {
        using var factory = Factory(new UnavailableReviewer());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/scrap/31/revisions",
            CreateRequest(true, 0));
        var text = await response.Content.ReadAsStringAsync();
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.DoesNotContain("synthetic database detail", text);
    }

    private static Request CreateRequest(bool cancellation, int quantity) =>
        new(25, 3, quantity, null, cancellation, 9, "Ajuste", Correlation);

    private static WebApplicationFactory<Program> Factory(IScrapReviewer reviewer) =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IScrapReviewer>();
                services.AddSingleton(reviewer);
            }));

    private sealed record Request(
        long OrderComponentId,
        short ScrapReasonId,
        int Quantity,
        string? Description,
        bool IsCancellation,
        long AdjustedBySupervisorId,
        string AdjustmentReason,
        Guid CorrelationId);

    private sealed class StubReviewer : IScrapReviewer
    {
        public Task<ReviewedScrapRecord> ReviewAsync(
            ReviewScrapCommand command,
            CancellationToken cancellationToken) =>
            Task.FromResult(new ReviewedScrapRecord(41, 44));
    }

    private sealed class RejectingReviewer : IScrapReviewer
    {
        public Task<ReviewedScrapRecord> ReviewAsync(
            ReviewScrapCommand command,
            CancellationToken cancellationToken) =>
            throw new ScrapRejectedException(
                "SCRAP_NAV_RESULT_PENDING_OR_UNKNOWN",
                "El resultado del consumo está en curso.");
    }

    private sealed class UnavailableReviewer : IScrapReviewer
    {
        public Task<ReviewedScrapRecord> ReviewAsync(
            ReviewScrapCommand command,
            CancellationToken cancellationToken) =>
            throw new ScrapUnavailableException("synthetic database detail");
    }
}
