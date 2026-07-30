using Ebir.Mes.Application.LineSessions;
using Xunit;

namespace Ebir.Mes.Application.Tests.LineSessions;

public sealed class FinishOperatorStopTests
{
    [Fact]
    public async Task ExecuteAsync_ReturnsStopAndOptionalSubstitution()
    {
        var result = await new FinishOperatorStop(new StubFinisher()).ExecuteAsync(
            new(12, 7, Guid.NewGuid()), CancellationToken.None);
        Assert.Equal(FinishOperatorStopOutcome.Finished, result.Outcome);
        Assert.Equal(31, result.Stop!.OperatorStopId);
        Assert.Equal(44, result.Stop.FinishedSubstitutionId);
        Assert.Equal(3, result.Stop.ActiveResources);
    }

    [Theory]
    [InlineData(0, 7, "LINE_SESSION_ID_INVALID")]
    [InlineData(12, 0, "EMPLOYEE_ID_INVALID")]
    public async Task ExecuteAsync_ValidatesIds(long session, long employee, string code)
    {
        var result = await new FinishOperatorStop(new StubFinisher()).ExecuteAsync(
            new(session, employee, Guid.NewGuid()), CancellationToken.None);
        Assert.Equal(code, result.ErrorCode);
    }

    [Fact]
    public async Task ExecuteAsync_ValidatesCorrelation()
    {
        var result = await new FinishOperatorStop(new StubFinisher()).ExecuteAsync(
            new(12, 7, Guid.Empty), CancellationToken.None);
        Assert.Equal("CORRELATION_ID_INVALID", result.ErrorCode);
    }

    private sealed class StubFinisher : IOperatorStopFinisher
    {
        public Task<FinishedOperatorStopRecord> FinishAsync(
            FinishOperatorStopCommand command, CancellationToken cancellationToken) =>
            Task.FromResult(new FinishedOperatorStopRecord(31, 44, 3));
    }
}
