using Ebir.Mes.Application.LineSessions;
using Xunit;

namespace Ebir.Mes.Application.Tests.LineSessions;

public sealed class RegisterProductiveExitTests
{
    [Fact]
    public async Task ExecuteAsync_RegistersAValidProductiveExit()
    {
        var registrar = new StubRegistrar(2);
        var command = ValidCommand();

        var result = await new RegisterProductiveExit(registrar)
            .ExecuteAsync(command, CancellationToken.None);

        Assert.Equal(ProductiveExitOutcome.Registered, result.Outcome);
        Assert.Equal(2, result.ActiveResources);
        Assert.Same(command, registrar.LastCommand);
    }

    [Theory]
    [InlineData(0, 2, "LINE_SESSION_ID_INVALID")]
    [InlineData(1, 0, "EMPLOYEE_ID_INVALID")]
    public async Task ExecuteAsync_RejectsNonPositiveIdentifiers(
        long sessionId,
        long employeeId,
        string expectedCode)
    {
        var registrar = new StubRegistrar(0);
        var command = new RegisterProductiveExitCommand(
            sessionId,
            employeeId,
            Guid.NewGuid());

        var result = await new RegisterProductiveExit(registrar)
            .ExecuteAsync(command, CancellationToken.None);

        Assert.Equal(ProductiveExitOutcome.InvalidRequest, result.Outcome);
        Assert.Equal(expectedCode, result.ErrorCode);
        Assert.Null(registrar.LastCommand);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsEmptyCorrelationId()
    {
        var registrar = new StubRegistrar(0);
        var result = await new RegisterProductiveExit(registrar).ExecuteAsync(
            ValidCommand() with { CorrelationId = Guid.Empty },
            CancellationToken.None);

        Assert.Equal(ProductiveExitOutcome.InvalidRequest, result.Outcome);
        Assert.Equal("CORRELATION_ID_INVALID", result.ErrorCode);
        Assert.Null(registrar.LastCommand);
    }

    [Fact]
    public async Task ExecuteAsync_ReturnsSafeFunctionalRejection()
    {
        var result = await new RegisterProductiveExit(new RejectingRegistrar())
            .ExecuteAsync(ValidCommand(), CancellationToken.None);

        Assert.Equal(ProductiveExitOutcome.Rejected, result.Outcome);
        Assert.Equal("EMPLOYEE_TIME_ENTRY_NOT_OPEN", result.ErrorCode);
    }

    private static RegisterProductiveExitCommand ValidCommand() =>
        new(1, 2, Guid.NewGuid());

    private sealed class StubRegistrar(int activeResources)
        : IProductiveExitRegistrar
    {
        public RegisterProductiveExitCommand? LastCommand { get; private set; }

        public Task<int> RegisterAsync(
            RegisterProductiveExitCommand command,
            CancellationToken cancellationToken)
        {
            LastCommand = command;
            return Task.FromResult(activeResources);
        }
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
}
