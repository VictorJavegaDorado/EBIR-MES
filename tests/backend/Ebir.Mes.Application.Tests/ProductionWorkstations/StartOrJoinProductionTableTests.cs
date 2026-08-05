using Ebir.Mes.Application.ProductionWorkstations;
using Xunit;

namespace Ebir.Mes.Application.Tests.ProductionWorkstations;

public sealed class StartOrJoinProductionTableTests
{
    [Fact]
    public async Task ExecuteAsync_StartsOrJoinsAValidTable()
    {
        var expected = new ProductionTableStartRecord(12, 31, 47, true);
        var starter = new StubStarter(expected);
        var command = ValidCommand();

        var result = await new StartOrJoinProductionTable(starter)
            .ExecuteAsync(command, CancellationToken.None);

        Assert.Equal(StartOrJoinProductionTableOutcome.StartedOrJoined, result.Outcome);
        Assert.Same(expected, result.Start);
        Assert.Same(command, starter.LastCommand);
    }

    [Theory]
    [InlineData(0, 2, 3, "ORDER_ID_INVALID")]
    [InlineData(1, 0, 3, "LINE_ID_INVALID")]
    [InlineData(1, 2, 0, "EMPLOYEE_ID_INVALID")]
    public async Task ExecuteAsync_RejectsInvalidIdentifiers(
        long orderId,
        long lineId,
        long employeeId,
        string expectedCode)
    {
        var starter = new StubStarter(new(12, 31, null, false));
        var result = await new StartOrJoinProductionTable(starter).ExecuteAsync(
            new(orderId, lineId, employeeId, Guid.NewGuid()),
            CancellationToken.None);

        Assert.Equal(StartOrJoinProductionTableOutcome.InvalidRequest, result.Outcome);
        Assert.Equal(expectedCode, result.ErrorCode);
        Assert.Null(starter.LastCommand);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsEmptyCorrelation()
    {
        var starter = new StubStarter(new(12, 31, null, false));

        var result = await new StartOrJoinProductionTable(starter).ExecuteAsync(
            ValidCommand() with { CorrelationId = Guid.Empty },
            CancellationToken.None);

        Assert.Equal(StartOrJoinProductionTableOutcome.InvalidRequest, result.Outcome);
        Assert.Equal("CORRELATION_ID_INVALID", result.ErrorCode);
        Assert.Null(starter.LastCommand);
    }

    [Fact]
    public async Task ExecuteAsync_ReturnsSafeFunctionalRejection()
    {
        var result = await new StartOrJoinProductionTable(new RejectingStarter())
            .ExecuteAsync(ValidCommand(), CancellationToken.None);

        Assert.Equal(StartOrJoinProductionTableOutcome.Rejected, result.Outcome);
        Assert.Equal("LINE_BUSY_WITH_ANOTHER_ORDER", result.ErrorCode);
    }

    private static StartOrJoinProductionTableCommand ValidCommand() =>
        new(1, 2, 3, Guid.NewGuid());

    private sealed class StubStarter(ProductionTableStartRecord start)
        : IProductionTableStarter
    {
        public StartOrJoinProductionTableCommand? LastCommand { get; private set; }

        public Task<ProductionTableStartRecord> StartOrJoinAsync(
            StartOrJoinProductionTableCommand command,
            CancellationToken cancellationToken)
        {
            LastCommand = command;
            return Task.FromResult(start);
        }
    }

    private sealed class RejectingStarter : IProductionTableStarter
    {
        public Task<ProductionTableStartRecord> StartOrJoinAsync(
            StartOrJoinProductionTableCommand command,
            CancellationToken cancellationToken) =>
            throw new ProductionTableRejectedException(
                "LINE_BUSY_WITH_ANOTHER_ORDER",
                "La línea está ocupada por otra orden.");
    }
}
