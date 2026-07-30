using Ebir.Mes.Application.LineSessions;
using Xunit;

namespace Ebir.Mes.Application.Tests.LineSessions;

public sealed class StartCapacitySubstitutionTests
{
    [Fact]
    public async Task ExecuteAsync_NormalizesReasonAndStartsSubstitution()
    {
        var starter = new StubStarter();
        var result = await new StartCapacitySubstitution(starter).ExecuteAsync(
            new(12, 7, 9, " cobertura temporal ", Guid.NewGuid()),
            CancellationToken.None);
        Assert.Equal(StartCapacitySubstitutionOutcome.Started, result.Outcome);
        Assert.Equal("cobertura temporal", starter.Command!.Reason);
        Assert.Equal(31, result.Substitution!.CapacitySubstitutionId);
    }

    [Theory]
    [InlineData(0, 7, 9, "motivo", "LINE_SESSION_ID_INVALID")]
    [InlineData(12, 0, 9, "motivo", "REPLACED_OPERATOR_ID_INVALID")]
    [InlineData(12, 7, 0, "motivo", "SUBSTITUTE_SUPERVISOR_ID_INVALID")]
    [InlineData(12, 7, 7, "motivo", "SUBSTITUTION_EMPLOYEES_MUST_DIFFER")]
    [InlineData(12, 7, 9, " ", "SUBSTITUTION_REASON_REQUIRED")]
    public async Task ExecuteAsync_ValidatesContract(
        long session, long replaced, long substitute, string reason, string code)
    {
        var result = await new StartCapacitySubstitution(new StubStarter()).ExecuteAsync(
            new(session, replaced, substitute, reason, Guid.NewGuid()),
            CancellationToken.None);
        Assert.Equal(code, result.ErrorCode);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsOversizedReason()
    {
        var result = await new StartCapacitySubstitution(new StubStarter()).ExecuteAsync(
            new(12, 7, 9,
                new string('x', StartCapacitySubstitution.MaximumReasonLength + 1),
                Guid.NewGuid()),
            CancellationToken.None);
        Assert.Equal("SUBSTITUTION_REASON_TOO_LONG", result.ErrorCode);
    }

    private sealed class StubStarter : ICapacitySubstitutionStarter
    {
        public StartCapacitySubstitutionCommand? Command { get; private set; }
        public Task<CapacitySubstitutionRecord> StartAsync(
            StartCapacitySubstitutionCommand command,
            CancellationToken cancellationToken)
        {
            Command = command;
            return Task.FromResult(new CapacitySubstitutionRecord(31, 44, 3));
        }
    }
}
