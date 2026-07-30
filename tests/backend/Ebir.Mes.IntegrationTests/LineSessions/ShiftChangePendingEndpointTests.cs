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

public sealed class ShiftChangePendingEndpointTests
{
    private static readonly Guid CorrelationId =
        Guid.Parse("0866010d-7872-4484-aa58-f62274b57076");

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task PostShiftChange_ReturnsTheIdempotentContract(bool marked)
    {
        using var factory = CreateFactory(new StubMarker(marked));
        using var client = factory.CreateClient();

        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/12/shift-change-pending",
            ValidRequest());
        using var body = JsonDocument.Parse(
            await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(marked, body.RootElement.GetProperty("changeMarked").GetBoolean());
        Assert.Equal(
            CorrelationId,
            body.RootElement.GetProperty("correlationId").GetGuid());
    }

    [Theory]
    [InlineData(0, "0866010d-7872-4484-aa58-f62274b57076", "LINE_SESSION_ID_INVALID")]
    [InlineData(12, "00000000-0000-0000-0000-000000000000", "CORRELATION_ID_INVALID")]
    public async Task PostShiftChange_ValidatesTheContract(
        long sessionId,
        string correlationId,
        string expectedCode)
    {
        using var factory = CreateFactory(new StubMarker(true));
        using var client = factory.CreateClient();

        using var response = await client.PostAsJsonAsync(
            $"/api/line-sessions/{sessionId}/shift-change-pending",
            new MarkShiftChangePendingRequest(Guid.Parse(correlationId)));
        using var body = JsonDocument.Parse(
            await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal(expectedCode, body.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task PostShiftChange_ReturnsConflictWithoutSqlDetails()
    {
        using var factory = CreateFactory(new RejectingMarker());
        using var client = factory.CreateClient();

        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/12/shift-change-pending",
            ValidRequest());
        var text = await response.Content.ReadAsStringAsync();
        using var body = JsonDocument.Parse(text);

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Equal(
            "SHIFT_CHANGE_NOT_REACHED",
            body.RootElement.GetProperty("code").GetString());
        Assert.DoesNotContain("52002", text);
    }

    [Fact]
    public async Task PostShiftChange_HidesInfrastructureFailure()
    {
        using var factory = CreateFactory(new UnavailableMarker());
        using var client = factory.CreateClient();

        using var response = await client.PostAsJsonAsync(
            "/api/line-sessions/12/shift-change-pending",
            ValidRequest());
        var text = await response.Content.ReadAsStringAsync();
        using var body = JsonDocument.Parse(text);

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.Equal(
            "LINE_SESSION_UNAVAILABLE",
            body.RootElement.GetProperty("code").GetString());
        Assert.DoesNotContain("synthetic database detail", text);
    }

    private static MarkShiftChangePendingRequest ValidRequest() =>
        new(CorrelationId);

    private static WebApplicationFactory<Program> CreateFactory(
        IShiftChangePendingMarker marker) =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IShiftChangePendingMarker>();
                services.AddSingleton(marker);
            }));

    private sealed record MarkShiftChangePendingRequest(Guid CorrelationId);

    private sealed class StubMarker(bool marked) : IShiftChangePendingMarker
    {
        public Task<bool> MarkAsync(
            MarkShiftChangePendingCommand command,
            CancellationToken cancellationToken) =>
            Task.FromResult(marked);
    }

    private sealed class RejectingMarker : IShiftChangePendingMarker
    {
        public Task<bool> MarkAsync(
            MarkShiftChangePendingCommand command,
            CancellationToken cancellationToken) =>
            throw new LineSessionRejectedException(
                "SHIFT_CHANGE_NOT_REACHED",
                "Todavía no se ha alcanzado el cambio de turno.");
    }

    private sealed class UnavailableMarker : IShiftChangePendingMarker
    {
        public Task<bool> MarkAsync(
            MarkShiftChangePendingCommand command,
            CancellationToken cancellationToken) =>
            throw new LineSessionUnavailableException("synthetic database detail");
    }
}
