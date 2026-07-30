using System.Net;
using System.Net.Http.Json;
using Ebir.Mes.Application.Pallets.ClosePallet;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Xunit;

namespace Ebir.Mes.IntegrationTests.Pallets;

public sealed class ClosePalletEndpointsTests
{
    [Fact]
    public async Task CloseAsync_ReturnsOkContract()
    {
        using var factory = CreateFactory(new StubCloser());
        var correlation = Guid.NewGuid();
        var response = await factory.CreateClient().PostAsJsonAsync("/api/pallet-reservations/12/close", new { goodQuantity = 20, closedByEmployeeId = 7, isPartial = false, correlationId = correlation });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<Response>();
        Assert.Equal(31, body!.Id); Assert.Equal(correlation, body.CorrelationId);
    }

    [Fact]
    public async Task CloseAsync_InvalidRequest_ReturnsSafeBadRequest()
    {
        using var factory = CreateFactory(new StubCloser());
        var response = await factory.CreateClient().PostAsJsonAsync("/api/pallet-reservations/0/close", new { goodQuantity = 0, closedByEmployeeId = 0, isPartial = false, correlationId = Guid.Empty });
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.DoesNotContain("554", await response.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task CloseAsync_Rejection_ReturnsSafeConflict()
    {
        using var factory = CreateFactory(new RejectingCloser());
        var response = await factory.CreateClient().PostAsJsonAsync("/api/pallet-reservations/12/close", new { goodQuantity = 20, closedByEmployeeId = 7, isPartial = false, correlationId = Guid.NewGuid() });
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.DoesNotContain("51403", await response.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task CloseAsync_Unavailable_ReturnsSafeServiceUnavailable()
    {
        using var factory = CreateFactory(new UnavailableCloser());
        var response = await factory.CreateClient().PostAsJsonAsync("/api/pallet-reservations/12/close", new { goodQuantity = 20, closedByEmployeeId = 7, isPartial = false, correlationId = Guid.NewGuid() });
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        var body = await response.Content.ReadAsStringAsync(); Assert.DoesNotContain("55401", body); Assert.DoesNotContain("55404", body); Assert.DoesNotContain("SqlException", body);
    }

    private static WebApplicationFactory<Program> CreateFactory(IPalletCloser closer) => new WebApplicationFactory<Program>().WithWebHostBuilder(builder => builder.UseEnvironment("Testing").ConfigureServices(services => services.Replace(ServiceDescriptor.Scoped<IPalletCloser>(_ => closer))));
    private sealed class StubCloser : IPalletCloser { public Task<ClosedPalletRecord> CloseAsync(ClosePalletCommand command, CancellationToken cancellationToken) => Task.FromResult(new ClosedPalletRecord(31)); }
    private sealed class RejectingCloser : IPalletCloser { public Task<ClosedPalletRecord> CloseAsync(ClosePalletCommand command, CancellationToken cancellationToken) => throw new PalletCloseRejectedException("ACTIVE_PALLET_RESERVATION_NOT_FOUND", "safe"); }
    private sealed class UnavailableCloser : IPalletCloser { public Task<ClosedPalletRecord> CloseAsync(ClosePalletCommand command, CancellationToken cancellationToken) => throw new PalletCloseUnavailableException("safe"); }
    private sealed record Response(long Id, Guid CorrelationId);
}
