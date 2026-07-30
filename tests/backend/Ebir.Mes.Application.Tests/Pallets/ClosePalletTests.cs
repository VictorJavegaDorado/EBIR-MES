using Ebir.Mes.Application.Pallets.ClosePallet;
using Xunit;

namespace Ebir.Mes.Application.Tests.Pallets;

public sealed class ClosePalletTests
{
    [Fact]
    public async Task ExecuteAsync_NormalizesPartialReasonAndCloses()
    {
        var closer = new StubCloser();
        var result = await new ClosePallet(closer).ExecuteAsync(new(1, 4, 7, 9, true, " fin_turno ", Guid.NewGuid()), CancellationToken.None);
        Assert.Equal(ClosePalletOutcome.Closed, result.Outcome);
        Assert.Equal("FIN_TURNO", closer.Command!.PartialReason);
        Assert.Equal(31, result.Pallet!.PalletId);
    }

    [Theory]
    [InlineData(0, 1, 1, "PALLET_RESERVATION_ID_INVALID")]
    [InlineData(1, 0, 1, "PALLET_GOOD_QUANTITY_INVALID")]
    [InlineData(1, 1, 0, "PALLET_CLOSER_ID_INVALID")]
    public async Task ExecuteAsync_ValidatesRequiredPositiveValues(long reservation, int quantity, long employee, string code)
    {
        var result = await new ClosePallet(new StubCloser()).ExecuteAsync(new(reservation, quantity, employee, null, false, null, Guid.NewGuid()), CancellationToken.None);
        Assert.Equal(ClosePalletOutcome.InvalidRequest, result.Outcome);
        Assert.Equal(code, result.ErrorCode);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsEmptyCorrelation() =>
        Assert.Equal("CORRELATION_ID_INVALID", (await new ClosePallet(new StubCloser()).ExecuteAsync(new(1, 1, 1, null, false, null, Guid.Empty), CancellationToken.None)).ErrorCode);

    [Theory]
    [InlineData(null, null, "PALLET_PARTIAL_SUPERVISOR_REQUIRED")]
    [InlineData(2L, null, "PALLET_PARTIAL_REASON_REQUIRED")]
    [InlineData(2L, "OTHER", "PALLET_PARTIAL_REASON_INVALID")]
    public async Task ExecuteAsync_ValidatesPartialClose(long? supervisor, string? reason, string code)
    {
        var result = await new ClosePallet(new StubCloser()).ExecuteAsync(new(1, 1, 1, supervisor, true, reason, Guid.NewGuid()), CancellationToken.None);
        Assert.Equal(code, result.ErrorCode);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsReasonForCompleteClose()
    {
        var result = await new ClosePallet(new StubCloser()).ExecuteAsync(new(1, 1, 1, null, false, "FIN_TURNO", Guid.NewGuid()), CancellationToken.None);
        Assert.Equal("PALLET_PARTIAL_REASON_NOT_ALLOWED", result.ErrorCode);
    }

    private sealed class StubCloser : IPalletCloser
    {
        public ClosePalletCommand? Command { get; private set; }
        public Task<ClosedPalletRecord> CloseAsync(ClosePalletCommand command, CancellationToken cancellationToken) { Command = command; return Task.FromResult(new ClosedPalletRecord(31)); }
    }
}
