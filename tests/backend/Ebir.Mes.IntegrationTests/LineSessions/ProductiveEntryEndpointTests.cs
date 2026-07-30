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

public sealed class ProductiveEntryEndpointTests
{
    private static readonly Guid CorrelationId =
        Guid.Parse("90557719-1b36-4124-af38-2078d2ac60b1");

    [Fact]
    public async Task PostProductiveEntry_ReturnsCreatedContract()
    {
        using var factory = CreateFactory(
            new StubRegistrar(new ProductiveEntryRecord(31, 47)));
        using var client = factory.CreateClient();

        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/12/entries",
            ValidRequest());
        using var body = JsonDocument.Parse(
            await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.Equal(
            "/api/line-sessions/12/entries/31",
            response.Headers.Location?.OriginalString);
        Assert.Equal(31, body.RootElement.GetProperty("id").GetInt64());
        Assert.Equal(
            47,
            body.RootElement.GetProperty("palletReservationId").GetInt64());
        Assert.Equal(
            CorrelationId,
            body.RootElement.GetProperty("correlationId").GetGuid());
    }

    [Fact]
    public async Task PostProductiveEntry_ReturnsNullWhenNoPalletWasReserved()
    {
        using var factory = CreateFactory(
            new StubRegistrar(new ProductiveEntryRecord(31, null)));
        using var client = factory.CreateClient();

        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/12/entries",
            ValidRequest());
        using var body = JsonDocument.Parse(
            await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.Equal(
            JsonValueKind.Null,
            body.RootElement.GetProperty("palletReservationId").ValueKind);
    }

    [Fact]
    public async Task PostProductiveEntry_ReturnsBadRequestForInvalidSessionId()
    {
        using var factory = CreateFactory(
            new StubRegistrar(new ProductiveEntryRecord(31, null)));
        using var client = factory.CreateClient();

        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/0/entries",
            ValidRequest());
        using var body = JsonDocument.Parse(
            await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal(
            "LINE_SESSION_ID_INVALID",
            body.RootElement.GetProperty("code").GetString());
    }

    [Theory]
    [InlineData(0, "5b96ea28-99b9-4aef-9b06-a8db2f201953", "EMPLOYEE_ID_INVALID")]
    [InlineData(5, "00000000-0000-0000-0000-000000000000", "CORRELATION_ID_INVALID")]
    public async Task PostProductiveEntry_ValidatesTheRequestBody(
        long employeeId,
        string correlationId,
        string expectedCode)
    {
        using var factory = CreateFactory(
            new StubRegistrar(new ProductiveEntryRecord(31, null)));
        using var client = factory.CreateClient();
        var request = new RegisterProductiveEntryRequest(
            employeeId,
            Guid.Parse(correlationId));

        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/12/entries",
            request);
        using var body = JsonDocument.Parse(
            await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal(expectedCode, body.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task PostProductiveEntry_ReturnsConflictWithSafeRejection()
    {
        using var factory = CreateFactory(new RejectingRegistrar());
        using var client = factory.CreateClient();

        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/12/entries",
            ValidRequest());
        var text = await response.Content.ReadAsStringAsync();
        using var body = JsonDocument.Parse(text);

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Equal(
            "EMPLOYEE_TIME_ENTRY_ALREADY_OPEN",
            body.RootElement.GetProperty("code").GetString());
        Assert.DoesNotContain("51808", text);
    }

    [Fact]
    public async Task PostProductiveEntry_HidesInfrastructureFailure()
    {
        using var factory = CreateFactory(new UnavailableRegistrar());
        using var client = factory.CreateClient();

        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/12/entries",
            ValidRequest());
        var text = await response.Content.ReadAsStringAsync();
        using var body = JsonDocument.Parse(text);

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.Equal(
            "LINE_SESSION_UNAVAILABLE",
            body.RootElement.GetProperty("code").GetString());
        Assert.DoesNotContain("synthetic database detail", text);
    }

    private static RegisterProductiveEntryRequest ValidRequest() =>
        new(5, CorrelationId);

    private static WebApplicationFactory<Program> CreateFactory(
        IProductiveEntryRegistrar registrar) =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IProductiveEntryRegistrar>();
                services.AddSingleton(registrar);
            }));

    private sealed record RegisterProductiveEntryRequest(
        long EmployeeId,
        Guid CorrelationId);

    private sealed class StubRegistrar(ProductiveEntryRecord entry)
        : IProductiveEntryRegistrar
    {
        public Task<ProductiveEntryRecord> RegisterAsync(
            RegisterProductiveEntryCommand command,
            CancellationToken cancellationToken) =>
            Task.FromResult(entry);
    }

    private sealed class RejectingRegistrar : IProductiveEntryRegistrar
    {
        public Task<ProductiveEntryRecord> RegisterAsync(
            RegisterProductiveEntryCommand command,
            CancellationToken cancellationToken) =>
            throw new LineSessionRejectedException(
                "EMPLOYEE_TIME_ENTRY_ALREADY_OPEN",
                "El operario ya tiene un fichaje productivo abierto.");
    }

    private sealed class UnavailableRegistrar : IProductiveEntryRegistrar
    {
        public Task<ProductiveEntryRecord> RegisterAsync(
            RegisterProductiveEntryCommand command,
            CancellationToken cancellationToken) =>
            throw new LineSessionUnavailableException("synthetic database detail");
    }
}
