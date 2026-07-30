using Ebir.Mes.Application.LineSessions;
using Xunit;

namespace Ebir.Mes.Application.Tests.LineSessions;

public sealed class StartOperatorStopTests
{
    [Fact]
    public async Task ExecuteAsync_NormalizesReasonAndStartsStop()
    {
        var starter = new StubStarter();
        var result = await new StartOperatorStop(starter).ExecuteAsync(
            new(12, 7, " pausa_calor ", Guid.NewGuid()), CancellationToken.None);
        Assert.Equal(StartOperatorStopOutcome.Started, result.Outcome);
        Assert.Equal("PAUSA_CALOR", starter.Command!.Reason);
        Assert.Equal(31, result.Stop!.OperatorStopId);
    }

    [Theory]
    [InlineData(0, 7, "WC", "LINE_SESSION_ID_INVALID")]
    [InlineData(12, 0, "WC", "EMPLOYEE_ID_INVALID")]
    [InlineData(12, 7, "OTRO", "STOP_REASON_INVALID")]
    public async Task ExecuteAsync_ValidatesContract(
        long sessionId, long employeeId, string reason, string code)
    {
        var starter = new StubStarter();
        var result = await new StartOperatorStop(starter).ExecuteAsync(
            new(sessionId, employeeId, reason, Guid.NewGuid()), CancellationToken.None);
        Assert.Equal(code, result.ErrorCode);
        Assert.Null(starter.Command);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsEmptyCorrelation()
    {
        var result = await new StartOperatorStop(new StubStarter()).ExecuteAsync(
            new(12, 7, "WC", Guid.Empty), CancellationToken.None);
        Assert.Equal("CORRELATION_ID_INVALID", result.ErrorCode);
    }

    private sealed class StubStarter : IOperatorStopStarter
    {
        public StartOperatorStopCommand? Command { get; private set; }
        public Task<OperatorStopRecord> StartAsync(
            StartOperatorStopCommand command, CancellationToken cancellationToken)
        {
            Command = command;
            return Task.FromResult(new OperatorStopRecord(31, 2));
        }
    }
}
