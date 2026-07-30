using Ebir.Mes.Application.LineSessions;
using Xunit;

namespace Ebir.Mes.Application.Tests.LineSessions;

public sealed class MarkShiftChangePendingTests
{
    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task ExecuteAsync_PreservesTheIdempotentResult(bool marked)
    {
        var marker = new StubMarker(marked);
        var command = ValidCommand();

        var result = await new MarkShiftChangePending(marker)
            .ExecuteAsync(command, CancellationToken.None);

        Assert.Equal(ShiftChangePendingOutcome.Processed, result.Outcome);
        Assert.Equal(marked, result.ChangeMarked);
        Assert.Same(command, marker.LastCommand);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsNonPositiveSessionId()
    {
        var marker = new StubMarker(true);

        var result = await new MarkShiftChangePending(marker).ExecuteAsync(
            ValidCommand() with { LineSessionId = 0 },
            CancellationToken.None);

        Assert.Equal(ShiftChangePendingOutcome.InvalidRequest, result.Outcome);
        Assert.Equal("LINE_SESSION_ID_INVALID", result.ErrorCode);
        Assert.Null(marker.LastCommand);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsEmptyCorrelationId()
    {
        var marker = new StubMarker(true);

        var result = await new MarkShiftChangePending(marker).ExecuteAsync(
            ValidCommand() with { CorrelationId = Guid.Empty },
            CancellationToken.None);

        Assert.Equal(ShiftChangePendingOutcome.InvalidRequest, result.Outcome);
        Assert.Equal("CORRELATION_ID_INVALID", result.ErrorCode);
        Assert.Null(marker.LastCommand);
    }

    [Fact]
    public async Task ExecuteAsync_ReturnsSafeFunctionalRejection()
    {
        var result = await new MarkShiftChangePending(new RejectingMarker())
            .ExecuteAsync(ValidCommand(), CancellationToken.None);

        Assert.Equal(ShiftChangePendingOutcome.Rejected, result.Outcome);
        Assert.Equal("SHIFT_CHANGE_NOT_REACHED", result.ErrorCode);
    }

    private static MarkShiftChangePendingCommand ValidCommand() =>
        new(12, Guid.NewGuid());

    private sealed class StubMarker(bool marked) : IShiftChangePendingMarker
    {
        public MarkShiftChangePendingCommand? LastCommand { get; private set; }

        public Task<bool> MarkAsync(
            MarkShiftChangePendingCommand command,
            CancellationToken cancellationToken)
        {
            LastCommand = command;
            return Task.FromResult(marked);
        }
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
}
