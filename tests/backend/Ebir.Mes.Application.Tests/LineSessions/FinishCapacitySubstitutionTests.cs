using Ebir.Mes.Application.LineSessions;
using Xunit;

namespace Ebir.Mes.Application.Tests.LineSessions;

public sealed class FinishCapacitySubstitutionTests
{
    [Fact]
    public async Task ExecuteAsync_NormalizesReasonAndFinishes()
    {
        var finisher = new StubFinisher();
        var result = await new FinishCapacitySubstitution(finisher).ExecuteAsync(
            new(31, 9, " fin cobertura ", Guid.NewGuid()),
            CancellationToken.None);
        Assert.Equal(FinishCapacitySubstitutionOutcome.Finished, result.Outcome);
        Assert.Equal(2, result.ActiveResources);
        Assert.Equal("fin cobertura", finisher.Command!.Reason);
    }

    [Theory]
    [InlineData(0, 9, "motivo", "CAPACITY_SUBSTITUTION_ID_INVALID")]
    [InlineData(31, 0, "motivo", "SUPERVISOR_ID_INVALID")]
    [InlineData(31, 9, " ", "SUBSTITUTION_FINISH_REASON_REQUIRED")]
    public async Task ExecuteAsync_ValidatesContract(
        long id, long supervisor, string reason, string code)
    {
        var result = await new FinishCapacitySubstitution(new StubFinisher())
            .ExecuteAsync(new(id, supervisor, reason, Guid.NewGuid()),
                CancellationToken.None);
        Assert.Equal(code, result.ErrorCode);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsOversizedReason()
    {
        var result = await new FinishCapacitySubstitution(new StubFinisher())
            .ExecuteAsync(
                new(
                    31,
                    9,
                    new string('x', FinishCapacitySubstitution.MaximumReasonLength + 1),
                    Guid.NewGuid()),
                CancellationToken.None);
        Assert.Equal("SUBSTITUTION_FINISH_REASON_TOO_LONG", result.ErrorCode);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsEmptyCorrelation()
    {
        var result = await new FinishCapacitySubstitution(new StubFinisher())
            .ExecuteAsync(
                new(31, 9, "motivo", Guid.Empty),
                CancellationToken.None);
        Assert.Equal("CORRELATION_ID_INVALID", result.ErrorCode);
    }

    private sealed class StubFinisher : ICapacitySubstitutionFinisher
    {
        public FinishCapacitySubstitutionCommand? Command { get; private set; }
        public Task<int> FinishAsync(
            FinishCapacitySubstitutionCommand command,
            CancellationToken cancellationToken)
        {
            Command = command;
            return Task.FromResult(2);
        }
    }
}
