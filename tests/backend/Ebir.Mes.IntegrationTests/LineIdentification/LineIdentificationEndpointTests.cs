using System.Net;
using System.Text.Json;
using Ebir.Mes.Application.LineIdentification;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Xunit;

namespace Ebir.Mes.IntegrationTests.LineIdentification;

public sealed class LineIdentificationEndpointTests
{
    [Fact]
    public async Task GetLine_ReturnsTheSafeOperationalContract()
    {
        var line = new LineIdentificationRecord(
            12,
            "L-01",
            "Línea uno",
            "CT-01",
            "Mecanizado",
            true,
            "LIBRE");
        using var factory = CreateFactory(new StubReader([line]));
        using var client = factory.CreateClient();

        using var response = await client.GetAsync("/api/lines/l-01");
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(12, body.RootElement.GetProperty("id").GetInt64());
        Assert.Equal("L-01", body.RootElement.GetProperty("code").GetString());
        Assert.Equal("Mecanizado", body.RootElement.GetProperty("workCenterName").GetString());
        Assert.Equal("LIBRE", body.RootElement.GetProperty("operationalStatus").GetString());
    }

    [Fact]
    public async Task GetLine_ReturnsNotFoundWithFunctionalCode()
    {
        using var factory = CreateFactory(new StubReader([]));
        using var client = factory.CreateClient();

        using var response = await client.GetAsync("/api/lines/L-99");
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.Equal("LINE_NOT_FOUND", body.RootElement.GetProperty("code").GetString());
        Assert.DoesNotContain("Sql", await response.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task GetLine_ReturnsBadRequestForAnOversizedCode()
    {
        using var factory = CreateFactory(new StubReader([]));
        using var client = factory.CreateClient();

        using var response = await client.GetAsync($"/api/lines/{new string('L', 21)}");
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("LINE_CODE_TOO_LONG", body.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task GetLine_ReturnsConflictForAnInactiveLine()
    {
        var inactiveLine = new LineIdentificationRecord(
            12,
            "L-01",
            "Línea uno",
            "CT-01",
            "Mecanizado",
            false,
            "FUERA_SERVICIO");
        using var factory = CreateFactory(new StubReader([inactiveLine]));
        using var client = factory.CreateClient();

        using var response = await client.GetAsync("/api/lines/L-01");
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Equal("LINE_INACTIVE", body.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task GetLine_ReturnsConflictInsteadOfSelectingAnAmbiguousLine()
    {
        var first = ActiveLine(12, "CT-01");
        var second = ActiveLine(18, "CT-02");
        using var factory = CreateFactory(new StubReader([first, second]));
        using var client = factory.CreateClient();

        using var response = await client.GetAsync("/api/lines/L-01");
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Equal("LINE_CODE_AMBIGUOUS", body.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task GetLine_HidesInfrastructureFailure()
    {
        using var factory = CreateFactory(new UnavailableReader());
        using var client = factory.CreateClient();

        using var response = await client.GetAsync("/api/lines/L-01");
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.Equal(
            "LINE_IDENTIFICATION_UNAVAILABLE",
            body.RootElement.GetProperty("code").GetString());
        Assert.DoesNotContain("synthetic database detail", await response.Content.ReadAsStringAsync());
    }

    private static WebApplicationFactory<Program> CreateFactory(
        ILineIdentificationReader reader)
    {
        return new WebApplicationFactory<Program>()
            .WithWebHostBuilder(builder =>
            {
                builder.ConfigureTestServices(services =>
                {
                    services.RemoveAll<ILineIdentificationReader>();
                    services.AddSingleton(reader);
                });
            });
    }

    private static LineIdentificationRecord ActiveLine(long id, string workCenterCode)
    {
        return new LineIdentificationRecord(
            id,
            "L-01",
            "Línea uno",
            workCenterCode,
            $"Centro {workCenterCode}",
            true,
            "LIBRE");
    }

    private sealed class StubReader(
        IReadOnlyList<LineIdentificationRecord> lines)
        : ILineIdentificationReader
    {
        public Task<IReadOnlyList<LineIdentificationRecord>> FindByCodeAsync(
            string normalizedCode,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(lines);
        }
    }

    private sealed class UnavailableReader : ILineIdentificationReader
    {
        public Task<IReadOnlyList<LineIdentificationRecord>> FindByCodeAsync(
            string normalizedCode,
            CancellationToken cancellationToken)
        {
            throw new LineIdentificationUnavailableException(
                "synthetic database detail");
        }
    }
}
