using Ebir.Mes.Application.Printing;
using Xunit;

namespace Ebir.Mes.Application.Tests.Printing;

public sealed class ReprintPalletLabelTests
{
    [Fact]
    public async Task ExecuteAsync_NormalizesReasonAndQueuesReprint()
    {
        var reprinter = new StubReprinter();
        var result = await new ReprintPalletLabel(reprinter).ExecuteAsync(
            new(29, 48, "  Etiqueta dañada  ", Guid.NewGuid()),
            CancellationToken.None);

        Assert.Equal(ReprintPalletLabelOutcome.Queued, result.Outcome);
        Assert.Equal(19, result.Reprint!.PrintJobId);
        Assert.Equal("Etiqueta dañada", reprinter.Command!.Reason);
    }

    [Theory]
    [InlineData(0, 48, "Motivo", "PALLET_ID_INVALID")]
    [InlineData(29, 0, "Motivo", "REPRINT_SUPERVISOR_ID_INVALID")]
    [InlineData(29, 48, " ", "REPRINT_REASON_REQUIRED")]
    public async Task ExecuteAsync_ValidatesRequiredFields(
        long palletId,
        long supervisorId,
        string reason,
        string code)
    {
        var result = await new ReprintPalletLabel(new StubReprinter()).ExecuteAsync(
            new(palletId, supervisorId, reason, Guid.NewGuid()),
            CancellationToken.None);

        Assert.Equal(ReprintPalletLabelOutcome.InvalidRequest, result.Outcome);
        Assert.Equal(code, result.ErrorCode);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsOversizedReason()
    {
        var result = await new ReprintPalletLabel(new StubReprinter()).ExecuteAsync(
            new(
                29,
                48,
                new string('x', ReprintPalletLabel.MaximumReasonLength + 1),
                Guid.NewGuid()),
            CancellationToken.None);

        Assert.Equal("REPRINT_REASON_TOO_LONG", result.ErrorCode);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsEmptyCorrelation()
    {
        var result = await new ReprintPalletLabel(new StubReprinter()).ExecuteAsync(
            new(29, 48, "Motivo", Guid.Empty),
            CancellationToken.None);

        Assert.Equal("CORRELATION_ID_INVALID", result.ErrorCode);
    }

    [Fact]
    public async Task ExecuteAsync_ReturnsFunctionalRejection()
    {
        var result = await new ReprintPalletLabel(new RejectingReprinter())
            .ExecuteAsync(
                new(29, 48, "Motivo", Guid.NewGuid()),
                CancellationToken.None);

        Assert.Equal(ReprintPalletLabelOutcome.Rejected, result.Outcome);
        Assert.Equal("PALLET_LABEL_NOT_PRINTED", result.ErrorCode);
    }

    private sealed class StubReprinter : IPalletLabelReprinter
    {
        public ReprintPalletLabelCommand? Command { get; private set; }

        public Task<ReprintedPalletLabelRecord> ReprintAsync(
            ReprintPalletLabelCommand command,
            CancellationToken cancellationToken)
        {
            Command = command;
            return Task.FromResult(new ReprintedPalletLabelRecord(19));
        }
    }

    private sealed class RejectingReprinter : IPalletLabelReprinter
    {
        public Task<ReprintedPalletLabelRecord> ReprintAsync(
            ReprintPalletLabelCommand command,
            CancellationToken cancellationToken) =>
            throw new PalletLabelReprintRejectedException(
                "PALLET_LABEL_NOT_PRINTED",
                "La etiqueta original todavía no consta como impresa.");
    }
}
