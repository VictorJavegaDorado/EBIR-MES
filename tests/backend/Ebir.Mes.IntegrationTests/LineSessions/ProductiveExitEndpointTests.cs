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

public sealed class ProductiveExitEndpointTests
{
    private static readonly Guid CorrelationId =
        Guid.Parse("a34c9544-0160-4628-a35b-e979219fa7b0");

    [Fact]
    public async Task PostProductiveExit_ReturnsTheRemainingResources()
    {
        using var factory = CreateFactory(new StubRegistrar(2));
        using var client = factory.CreateClient();

        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/12/exits",
            ValidRequest());
        using var body = JsonDocument.Parse(
            await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(2, body.RootElement.GetProperty("activeResources").GetInt32());
        Assert.Equal(
            CorrelationId,
            body.RootElement.GetProperty("correlationId").GetGuid());
    }

    [Theory]
    [InlineData(0, 5, "a34c9544-0160-4628-a35b-e979219fa7b0", "LINE_SESSION_ID_INVALID")]
    [InlineData(12, 0, "a34c9544-0160-4628-a35b-e979219fa7b0", "EMPLOYEE_ID_INVALID")]
    [InlineData(12, 5, "00000000-0000-0000-0000-000000000000", "CORRELATION_ID_INVALID")]
    public async Task PostProductiveExit_ValidatesTheContract(
        long sessionId,
        long employeeId,
        string correlationId,
        string expectedCode)
    {
        using var factory = CreateFactory(new StubRegistrar(0));
        using var client = factory.CreateClient();
        var request = new RegisterProductiveExitRequest(
            employeeId,
            Guid.Parse(correlationId));

        using var response = await client.PostAsJsonAsync(
            $"/api/line-sessions/{sessionId}/exits",
            request);
        using var body = JsonDocument.Parse(
            await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal(expectedCode, body.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task PostProductiveExit_ReturnsConflictWithoutSqlDetails()
    {
        using var factory = CreateFactory(new RejectingRegistrar());
        using var client = factory.CreateClient();

        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/12/exits",
            ValidRequest());
        var text = await response.Content.ReadAsStringAsync();
        using var body = JsonDocument.Parse(text);

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Equal(
            "EMPLOYEE_TIME_ENTRY_NOT_OPEN",
            body.RootElement.GetProperty("code").GetString());
        Assert.DoesNotContain("51907", text);
    }

    [Fact]
    public async Task PostProductiveExit_HidesInfrastructureFailure()
    {
        using var factory = CreateFactory(new UnavailableRegistrar());
        using var client = factory.CreateClient();

        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/12/exits",
            ValidRequest());
        var text = await response.Content.ReadAsStringAsync();
        using var body = JsonDocument.Parse(text);

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.Equal(
            "LINE_SESSION_UNAVAILABLE",
            body.RootElement.GetProperty("code").GetString());
        Assert.DoesNotContain("synthetic database detail", text);
    }

    private static RegisterProductiveExitRequest ValidRequest() =>
        new(5, CorrelationId);

    private static WebApplicationFactory<Program> CreateFactory(
        IProductiveExitRegistrar registrar) =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IProductiveExitRegistrar>();
                services.AddSingleton(registrar);
            }));

    private sealed record RegisterProductiveExitRequest(
        long EmployeeId,
        Guid CorrelationId);

    private sealed class StubRegistrar(int activeResources)
        : IProductiveExitRegistrar
    {
        public Task<int> RegisterAsync(
            RegisterProductiveExitCommand command,
            CancellationToken cancellationToken) =>
            Task.FromResult(activeResources);
    }

    private sealed class RejectingRegistrar : IProductiveExitRegistrar
    {
        public Task<int> RegisterAsync(
            RegisterProductiveExitCommand command,
            CancellationToken cancellationToken) =>
            throw new LineSessionRejectedException(
                "EMPLOYEE_TIME_ENTRY_NOT_OPEN",
                "El operario no tiene un fichaje productivo abierto en la sesión.");
    }

    private sealed class UnavailableRegistrar : IProductiveExitRegistrar
    {
        public Task<int> RegisterAsync(
            RegisterProductiveExitCommand command,
            CancellationToken cancellationToken) =>
            throw new LineSessionUnavailableException("synthetic database detail");
    }
}
