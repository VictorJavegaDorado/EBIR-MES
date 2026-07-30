using Ebir.Mes.Application.LineSessions;
using Xunit;

namespace Ebir.Mes.Application.Tests.LineSessions;

public sealed class FinishLineSessionTests
{
    [Fact]
    public async Task ExecuteAsync_FinishesAValidSession()
    {
        var finisher = new StubFinisher(3);
        var command = new FinishLineSessionCommand(12, 7, Guid.NewGuid());

        var result = await new FinishLineSession(finisher)
            .ExecuteAsync(command, CancellationToken.None);

        Assert.Equal(FinishLineSessionOutcome.Finished, result.Outcome);
        Assert.Equal(3, result.ClosedTimeEntries);
        Assert.Same(command, finisher.Command);
    }

    [Theory]
    [InlineData(0, 7, "LINE_SESSION_ID_INVALID")]
    [InlineData(12, 0, "SUPERVISOR_ID_INVALID")]
    public async Task ExecuteAsync_RejectsInvalidIdentifiers(
        long sessionId, long supervisorId, string code)
    {
        var finisher = new StubFinisher(0);
        var result = await new FinishLineSession(finisher).ExecuteAsync(
            new(sessionId, supervisorId, Guid.NewGuid()), CancellationToken.None);
        Assert.Equal(FinishLineSessionOutcome.InvalidRequest, result.Outcome);
        Assert.Equal(code, result.ErrorCode);
        Assert.Null(finisher.Command);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsEmptyCorrelation()
    {
        var result = await new FinishLineSession(new StubFinisher(0)).ExecuteAsync(
            new(12, 7, Guid.Empty), CancellationToken.None);
        Assert.Equal("CORRELATION_ID_INVALID", result.ErrorCode);
    }

    private sealed class StubFinisher(int closed) : ILineSessionFinisher
    {
        public FinishLineSessionCommand? Command { get; private set; }
        public Task<int> FinishAsync(
            FinishLineSessionCommand command, CancellationToken cancellationToken)
        {
            Command = command;
            return Task.FromResult(closed);
        }
    }
}
