using Ebir.Mes.Application.Scrap;
using Xunit;

namespace Ebir.Mes.Application.Tests.Scrap;

public sealed class ReviewScrapTests
{
    [Fact]
    public async Task ExecuteAsync_NormalizesTextsAndReviews()
    {
        var reviewer = new StubReviewer();
        var result = await new ReviewScrap(reviewer).ExecuteAsync(
            new(31, 25, 3, 2, " ajuste ", false, 9, " corrección ", Guid.NewGuid()),
            CancellationToken.None);
        Assert.Equal(ReviewScrapOutcome.Reviewed, result.Outcome);
        Assert.Equal("ajuste", reviewer.Command!.Description);
        Assert.Equal("corrección", reviewer.Command.AdjustmentReason);
        Assert.Equal(41, result.Revision!.ScrapRevisionId);
    }

    [Theory]
    [InlineData(false, 0)]
    [InlineData(false, -1)]
    [InlineData(true, 1)]
    [InlineData(true, -1)]
    public async Task ExecuteAsync_ValidatesQuantityForReviewType(
        bool cancellation,
        int quantity)
    {
        var result = await new ReviewScrap(new StubReviewer()).ExecuteAsync(
            new(31, 25, 3, quantity, null, cancellation, 9, "motivo", Guid.NewGuid()),
            CancellationToken.None);
        Assert.Equal("SCRAP_REVIEW_QUANTITY_INVALID", result.ErrorCode);
    }

    [Theory]
    [InlineData(0, 25, 3, 9, "motivo", "SCRAP_ID_INVALID")]
    [InlineData(31, 0, 3, 9, "motivo", "ORDER_COMPONENT_ID_INVALID")]
    [InlineData(31, 25, 0, 9, "motivo", "SCRAP_REASON_ID_INVALID")]
    [InlineData(31, 25, 3, 0, "motivo", "ADJUSTED_BY_SUPERVISOR_ID_INVALID")]
    [InlineData(31, 25, 3, 9, " ", "SCRAP_ADJUSTMENT_REASON_REQUIRED")]
    public async Task ExecuteAsync_ValidatesContract(
        long scrap,
        long component,
        short reason,
        long supervisor,
        string adjustmentReason,
        string code)
    {
        var result = await new ReviewScrap(new StubReviewer()).ExecuteAsync(
            new(
                scrap,
                component,
                reason,
                2,
                null,
                false,
                supervisor,
                adjustmentReason,
                Guid.NewGuid()),
            CancellationToken.None);
        Assert.Equal(code, result.ErrorCode);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsOversizedTexts()
    {
        var useCase = new ReviewScrap(new StubReviewer());
        var description = await useCase.ExecuteAsync(
            new(
                31,
                25,
                3,
                2,
                new string('x', ReviewScrap.MaximumDescriptionLength + 1),
                false,
                9,
                "motivo",
                Guid.NewGuid()),
            CancellationToken.None);
        var reason = await useCase.ExecuteAsync(
            new(
                31,
                25,
                3,
                2,
                null,
                false,
                9,
                new string('x', ReviewScrap.MaximumAdjustmentReasonLength + 1),
                Guid.NewGuid()),
            CancellationToken.None);
        Assert.Equal("SCRAP_DESCRIPTION_TOO_LONG", description.ErrorCode);
        Assert.Equal("SCRAP_ADJUSTMENT_REASON_TOO_LONG", reason.ErrorCode);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsEmptyCorrelation()
    {
        var result = await new ReviewScrap(new StubReviewer()).ExecuteAsync(
            new(31, 25, 3, 2, null, false, 9, "motivo", Guid.Empty),
            CancellationToken.None);
        Assert.Equal("CORRELATION_ID_INVALID", result.ErrorCode);
    }

    private sealed class StubReviewer : IScrapReviewer
    {
        public ReviewScrapCommand? Command { get; private set; }

        public Task<ReviewedScrapRecord> ReviewAsync(
            ReviewScrapCommand command,
            CancellationToken cancellationToken)
        {
            Command = command;
            return Task.FromResult(new ReviewedScrapRecord(41, 44));
        }
    }
}
