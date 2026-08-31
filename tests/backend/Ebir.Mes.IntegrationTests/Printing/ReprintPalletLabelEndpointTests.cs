using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Ebir.Mes.Application.Printing;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Xunit;

namespace Ebir.Mes.IntegrationTests.Printing;

public sealed class ReprintPalletLabelEndpointTests
{
    private static readonly Guid Correlation = Guid.NewGuid();

    [Fact]
    public async Task PostReprint_ReturnsCreatedContract()
    {
        using var factory = Factory(new StubReprinter());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/pallets/29/label-reprints",
            CreateRequest());
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.Equal(19, body.RootElement.GetProperty("id").GetInt64());
        Assert.Equal(29, body.RootElement.GetProperty("palletId").GetInt64());
        Assert.Equal(
            Correlation,
            body.RootElement.GetProperty("correlationId").GetGuid());
    }

    [Fact]
    public async Task PostReprint_ReturnsBadRequest()
    {
        using var factory = Factory(new StubReprinter());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/pallets/0/label-reprints",
            CreateRequest());
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal(
            "PALLET_ID_INVALID",
            body.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task PostReprint_ReturnsSafeConflict()
    {
        using var factory = Factory(new RejectingReprinter());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/pallets/29/label-reprints",
            CreateRequest());
        var text = await response.Content.ReadAsStringAsync();
        using var body = JsonDocument.Parse(text);

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Equal(
            "PALLET_LABEL_PRINT_ALREADY_OPEN",
            body.RootElement.GetProperty("code").GetString());
        Assert.DoesNotContain("56512", text);
    }

    [Fact]
    public async Task PostReprint_HidesInfrastructureFailure()
    {
        using var factory = Factory(new UnavailableReprinter());
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/pallets/29/label-reprints",
            CreateRequest());
        var text = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.DoesNotContain("synthetic database detail", text);
    }

    private static Request CreateRequest() =>
        new(48, "Etiqueta dañada", Correlation);

    private static WebApplicationFactory<Program> Factory(
        IPalletLabelReprinter reprinter) =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IPalletLabelReprinter>();
                services.AddSingleton(reprinter);
            }));

    private sealed record Request(
        long RequestedBySupervisorId,
        string Reason,
        Guid CorrelationId);

    private sealed class StubReprinter : IPalletLabelReprinter
    {
        public Task<ReprintedPalletLabelRecord> ReprintAsync(
            ReprintPalletLabelCommand command,
            CancellationToken cancellationToken) =>
            Task.FromResult(new ReprintedPalletLabelRecord(19));
    }

    private sealed class RejectingReprinter : IPalletLabelReprinter
    {
        public Task<ReprintedPalletLabelRecord> ReprintAsync(
            ReprintPalletLabelCommand command,
            CancellationToken cancellationToken) =>
            throw new PalletLabelReprintRejectedException(
                "PALLET_LABEL_PRINT_ALREADY_OPEN",
                "Ya existe una impresión pendiente.");
    }

    private sealed class UnavailableReprinter : IPalletLabelReprinter
    {
        public Task<ReprintedPalletLabelRecord> ReprintAsync(
            ReprintPalletLabelCommand command,
            CancellationToken cancellationToken) =>
            throw new PalletLabelReprintUnavailableException(
                "synthetic database detail");
    }
}
