using Ebir.Mes.Application.LineSessions;
using Xunit;

namespace Ebir.Mes.Application.Tests.LineSessions;

public sealed class RegisterProductiveEntryTests
{
    [Fact]
    public async Task ExecuteAsync_RegistersAValidProductiveEntry()
    {
        var expected = new ProductiveEntryRecord(31, 47);
        var registrar = new StubRegistrar(expected);
        var command = ValidCommand();

        var result = await new RegisterProductiveEntry(registrar)
            .ExecuteAsync(command, CancellationToken.None);

        Assert.Equal(ProductiveEntryOutcome.Registered, result.Outcome);
        Assert.Same(expected, result.Entry);
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
        var registrar = new StubRegistrar(new ProductiveEntryRecord(31, null));
        var command = new RegisterProductiveEntryCommand(
            sessionId,
            employeeId,
            Guid.NewGuid());

        var result = await new RegisterProductiveEntry(registrar)
            .ExecuteAsync(command, CancellationToken.None);

        Assert.Equal(ProductiveEntryOutcome.InvalidRequest, result.Outcome);
        Assert.Equal(expectedCode, result.ErrorCode);
        Assert.Null(registrar.LastCommand);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsEmptyCorrelationId()
    {
        var registrar = new StubRegistrar(new ProductiveEntryRecord(31, null));

        var result = await new RegisterProductiveEntry(registrar).ExecuteAsync(
            ValidCommand() with { CorrelationId = Guid.Empty },
            CancellationToken.None);

        Assert.Equal(ProductiveEntryOutcome.InvalidRequest, result.Outcome);
        Assert.Equal("CORRELATION_ID_INVALID", result.ErrorCode);
        Assert.Null(registrar.LastCommand);
    }

    [Fact]
    public async Task ExecuteAsync_ReturnsSafeFunctionalRejection()
    {
        var result = await new RegisterProductiveEntry(new RejectingRegistrar())
            .ExecuteAsync(ValidCommand(), CancellationToken.None);

        Assert.Equal(ProductiveEntryOutcome.Rejected, result.Outcome);
        Assert.Equal("EMPLOYEE_TIME_ENTRY_ALREADY_OPEN", result.ErrorCode);
        Assert.Equal(
            "El operario ya tiene un fichaje productivo abierto.",
            result.ErrorMessage);
    }

    private static RegisterProductiveEntryCommand ValidCommand() =>
        new(1, 2, Guid.NewGuid());

    private sealed class StubRegistrar(ProductiveEntryRecord entry)
        : IProductiveEntryRegistrar
    {
        public RegisterProductiveEntryCommand? LastCommand { get; private set; }

        public Task<ProductiveEntryRecord> RegisterAsync(
            RegisterProductiveEntryCommand command,
            CancellationToken cancellationToken)
        {
            LastCommand = command;
            return Task.FromResult(entry);
        }
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
}
