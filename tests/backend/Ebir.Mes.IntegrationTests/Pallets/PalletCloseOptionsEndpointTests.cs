using System.Net;
using System.Text.Json;
using Ebir.Mes.Application.Pallets.ClosePalletOptions;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Xunit;

namespace Ebir.Mes.IntegrationTests.Pallets;

public sealed class PalletCloseOptionsEndpointTests
{
    [Fact]
    public async Task GetOptions_ReturnsLineScopedReservationsAndEligibleEmployees()
    {
        var options = new PalletCloseOptionsRecord(
            [new(44, 20, "OT-100")],
            [new(7, "EMP-7", "Operario siete")],
            [new(9, "EMP-9", "Supervisora nueve")]);
        using var factory = CreateFactory(new StubReader(options));
        using var client = factory.CreateClient();

        using var response = await client.GetAsync(
            "/api/lines/12/pallet-close-options");
        using var body = JsonDocument.Parse(
            await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(44, body.RootElement
            .GetProperty("reservations")[0].GetProperty("id").GetInt64());
        Assert.Equal("Operario siete", body.RootElement
            .GetProperty("employees")[0].GetProperty("name").GetString());
        Assert.Equal("Supervisora nueve", body.RootElement
            .GetProperty("supervisors")[0].GetProperty("name").GetString());
    }

    [Fact]
    public async Task GetOptions_RejectsAnInvalidLineWithoutReading()
    {
        var reader = new StubReader(new([], [], []));
        using var factory = CreateFactory(reader);
        using var client = factory.CreateClient();

        using var response = await client.GetAsync(
            "/api/lines/0/pallet-close-options");
        using var body = JsonDocument.Parse(
            await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal(
            "LINE_ID_INVALID",
            body.RootElement.GetProperty("code").GetString());
        Assert.Equal(0, reader.CallCount);
    }

    [Fact]
    public async Task GetOptions_HidesInfrastructureFailure()
    {
        using var factory = CreateFactory(new UnavailableReader());
        using var client = factory.CreateClient();

        using var response = await client.GetAsync(
            "/api/lines/12/pallet-close-options");
        var content = await response.Content.ReadAsStringAsync();
        using var body = JsonDocument.Parse(content);

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.Equal(
            "PALLET_CLOSE_OPTIONS_UNAVAILABLE",
            body.RootElement.GetProperty("code").GetString());
        Assert.DoesNotContain("synthetic database detail", content);
    }

    private static WebApplicationFactory<Program> CreateFactory(
        IPalletCloseOptionsReader reader) =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IPalletCloseOptionsReader>();
                services.AddSingleton(reader);
            });
        });

    private sealed class StubReader(PalletCloseOptionsRecord options)
        : IPalletCloseOptionsReader
    {
        public int CallCount { get; private set; }

        public Task<PalletCloseOptionsRecord> ReadAsync(
            long lineId,
            CancellationToken cancellationToken)
        {
            CallCount++;
            return Task.FromResult(options);
        }
    }

    private sealed class UnavailableReader : IPalletCloseOptionsReader
    {
        public Task<PalletCloseOptionsRecord> ReadAsync(
            long lineId,
            CancellationToken cancellationToken) =>
            throw new PalletCloseOptionsUnavailableException(
                "synthetic database detail");
    }
}
