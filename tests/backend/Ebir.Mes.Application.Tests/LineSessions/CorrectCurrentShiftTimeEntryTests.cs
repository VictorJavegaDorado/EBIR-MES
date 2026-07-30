using Ebir.Mes.Application.LineSessions;
using Xunit;

namespace Ebir.Mes.Application.Tests.LineSessions;

public sealed class CorrectCurrentShiftTimeEntryTests
{
    private static readonly DateTimeOffset Entry =
        new(2026, 7, 30, 6, 0, 0, TimeSpan.FromHours(2));

    [Fact]
    public async Task ExecuteAsync_NormalizesValuesAndCorrects()
    {
        var corrector = new StubCorrector();
        var result = await new CorrectCurrentShiftTimeEntry(corrector).ExecuteAsync(
            new(44, Entry, Entry.AddHours(2), 9, " ajuste de turno ", Guid.NewGuid()),
            CancellationToken.None);
        Assert.Equal(CorrectCurrentShiftTimeEntryOutcome.Corrected, result.Outcome);
        Assert.Equal("ajuste de turno", corrector.Command!.Reason);
        Assert.Equal(TimeSpan.Zero, corrector.Command.CorrectedEntryUtc.Offset);
        Assert.Equal(TimeSpan.Zero, corrector.Command.CorrectedExitUtc!.Value.Offset);
    }

    [Theory]
    [InlineData(0, 9, "motivo", "TIME_ENTRY_ID_INVALID")]
    [InlineData(44, 0, "motivo", "SUPERVISOR_ID_INVALID")]
    [InlineData(44, 9, " ", "TIME_ENTRY_CORRECTION_REASON_REQUIRED")]
    public async Task ExecuteAsync_ValidatesIdentifiersAndReason(
        long id, long supervisor, string reason, string code)
    {
        var result = await new CorrectCurrentShiftTimeEntry(new StubCorrector())
            .ExecuteAsync(
                new(id, Entry, null, supervisor, reason, Guid.NewGuid()),
                CancellationToken.None);
        Assert.Equal(code, result.ErrorCode);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsMissingEntry()
    {
        var result = await new CorrectCurrentShiftTimeEntry(new StubCorrector())
            .ExecuteAsync(
                new(44, default, null, 9, "motivo", Guid.NewGuid()),
                CancellationToken.None);
        Assert.Equal("CORRECTED_ENTRY_UTC_REQUIRED", result.ErrorCode);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsExitBeforeEntry()
    {
        var result = await new CorrectCurrentShiftTimeEntry(new StubCorrector())
            .ExecuteAsync(
                new(44, Entry, Entry.AddMinutes(-1), 9, "motivo", Guid.NewGuid()),
                CancellationToken.None);
        Assert.Equal("CORRECTED_EXIT_BEFORE_ENTRY", result.ErrorCode);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsOversizedReason()
    {
        var result = await new CorrectCurrentShiftTimeEntry(new StubCorrector())
            .ExecuteAsync(
                new(
                    44,
                    Entry,
                    null,
                    9,
                    new string('x', CorrectCurrentShiftTimeEntry.MaximumReasonLength + 1),
                    Guid.NewGuid()),
                CancellationToken.None);
        Assert.Equal("TIME_ENTRY_CORRECTION_REASON_TOO_LONG", result.ErrorCode);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsEmptyCorrelation()
    {
        var result = await new CorrectCurrentShiftTimeEntry(new StubCorrector())
            .ExecuteAsync(
                new(44, Entry, null, 9, "motivo", Guid.Empty),
                CancellationToken.None);
        Assert.Equal("CORRELATION_ID_INVALID", result.ErrorCode);
    }

    private sealed class StubCorrector : ICurrentShiftTimeEntryCorrector
    {
        public CorrectCurrentShiftTimeEntryCommand? Command { get; private set; }

        public Task CorrectAsync(
            CorrectCurrentShiftTimeEntryCommand command,
            CancellationToken cancellationToken)
        {
            Command = command;
            return Task.CompletedTask;
        }
    }
}
