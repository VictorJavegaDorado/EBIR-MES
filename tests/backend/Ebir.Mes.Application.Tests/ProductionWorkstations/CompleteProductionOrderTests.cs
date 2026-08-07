using Ebir.Mes.Application.ProductionWorkstations;
using Xunit;

namespace Ebir.Mes.Application.Tests.ProductionWorkstations;

public sealed class CompleteProductionOrderTests
{
    [Fact]
    public async Task ExecuteAsync_CompletesAValidOrder()
    {
        var completer = new StubCompleter();
        var command = new CompleteProductionOrderCommand(12, Guid.NewGuid());

        var result = await new CompleteProductionOrder(completer)
            .ExecuteAsync(command, CancellationToken.None);

        Assert.Equal(CompleteProductionOrderOutcome.Completed, result.Outcome);
        Assert.Same(command, completer.LastCommand);
    }

    [Theory]
    [InlineData(0, false, "LINE_SESSION_ID_INVALID")]
    [InlineData(12, true, "CORRELATION_ID_INVALID")]
    public async Task ExecuteAsync_RejectsInvalidRequests(
        long sessionId,
        bool emptyCorrelation,
        string expectedCode)
    {
        var completer = new StubCompleter();
        var result = await new CompleteProductionOrder(completer).ExecuteAsync(
            new(sessionId, emptyCorrelation ? Guid.Empty : Guid.NewGuid()),
            CancellationToken.None);

        Assert.Equal(CompleteProductionOrderOutcome.InvalidRequest, result.Outcome);
        Assert.Equal(expectedCode, result.ErrorCode);
        Assert.Null(completer.LastCommand);
    }

    [Fact]
    public async Task ExecuteAsync_ReturnsSafeFunctionalRejection()
    {
        var result = await new CompleteProductionOrder(new RejectingCompleter())
            .ExecuteAsync(new(12, Guid.NewGuid()), CancellationToken.None);

        Assert.Equal(CompleteProductionOrderOutcome.Rejected, result.Outcome);
        Assert.Equal("PALLET_OUTPUT_NOT_CONFIRMED", result.ErrorCode);
    }

    private sealed class StubCompleter : IProductionOrderCompleter
    {
        public CompleteProductionOrderCommand? LastCommand { get; private set; }

        public Task CompleteAsync(
            CompleteProductionOrderCommand command,
            CancellationToken cancellationToken)
        {
            LastCommand = command;
            return Task.CompletedTask;
        }
    }

    private sealed class RejectingCompleter : IProductionOrderCompleter
    {
        public Task CompleteAsync(
            CompleteProductionOrderCommand command,
            CancellationToken cancellationToken) =>
            throw new ProductionTableRejectedException(
                "PALLET_OUTPUT_NOT_CONFIRMED",
                "Las salidas todavía no están confirmadas.");
    }
}
