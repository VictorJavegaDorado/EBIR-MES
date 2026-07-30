using Ebir.Mes.Application.Scrap;
using Xunit;

namespace Ebir.Mes.Application.Tests.Scrap;

public sealed class RegisterScrapTests
{
    [Fact]
    public async Task ExecuteAsync_NormalizesDescriptionAndRegisters()
    {
        var registrar = new StubRegistrar();
        var result = await new RegisterScrap(registrar).ExecuteAsync(
            new(12, 25, 3, 4, " pieza dañada ", 7, Guid.NewGuid()),
            CancellationToken.None);
        Assert.Equal(RegisterScrapOutcome.Registered, result.Outcome);
        Assert.Equal("pieza dañada", registrar.Command!.Description);
        Assert.Equal(31, result.Scrap!.ScrapId);
        Assert.Equal(44, result.Scrap.NavOperationId);
    }

    [Fact]
    public async Task ExecuteAsync_NormalizesBlankDescriptionToNull()
    {
        var registrar = new StubRegistrar();
        await new RegisterScrap(registrar).ExecuteAsync(
            new(12, 25, 3, 4, " ", 7, Guid.NewGuid()),
            CancellationToken.None);
        Assert.Null(registrar.Command!.Description);
    }

    [Theory]
    [InlineData(0, 25, 3, 4, 7, "LINE_SESSION_ID_INVALID")]
    [InlineData(12, 0, 3, 4, 7, "ORDER_COMPONENT_ID_INVALID")]
    [InlineData(12, 25, 0, 4, 7, "SCRAP_REASON_ID_INVALID")]
    [InlineData(12, 25, 3, 0, 7, "SCRAP_QUANTITY_INVALID")]
    [InlineData(12, 25, 3, 4, 0, "REGISTERED_BY_EMPLOYEE_ID_INVALID")]
    public async Task ExecuteAsync_ValidatesPositiveValues(
        long session,
        long component,
        short reason,
        int quantity,
        long employee,
        string code)
    {
        var result = await new RegisterScrap(new StubRegistrar()).ExecuteAsync(
            new(session, component, reason, quantity, null, employee, Guid.NewGuid()),
            CancellationToken.None);
        Assert.Equal(code, result.ErrorCode);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsOversizedDescription()
    {
        var result = await new RegisterScrap(new StubRegistrar()).ExecuteAsync(
            new(
                12,
                25,
                3,
                4,
                new string('x', RegisterScrap.MaximumDescriptionLength + 1),
                7,
                Guid.NewGuid()),
            CancellationToken.None);
        Assert.Equal("SCRAP_DESCRIPTION_TOO_LONG", result.ErrorCode);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsEmptyCorrelation()
    {
        var result = await new RegisterScrap(new StubRegistrar()).ExecuteAsync(
            new(12, 25, 3, 4, null, 7, Guid.Empty),
            CancellationToken.None);
        Assert.Equal("CORRELATION_ID_INVALID", result.ErrorCode);
    }

    private sealed class StubRegistrar : IScrapRegistrar
    {
        public RegisterScrapCommand? Command { get; private set; }

        public Task<RegisteredScrapRecord> RegisterAsync(
            RegisterScrapCommand command,
            CancellationToken cancellationToken)
        {
            Command = command;
            return Task.FromResult(new RegisteredScrapRecord(31, 44));
        }
    }
}
