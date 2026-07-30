namespace Ebir.Mes.Application.Scrap;

public sealed class ReviewScrap(IScrapReviewer reviewer)
{
    public const int MaximumDescriptionLength = 1000;
    public const int MaximumAdjustmentReasonLength = 500;

    public async Task<ReviewScrapResult> ExecuteAsync(
        ReviewScrapCommand command,
        CancellationToken cancellationToken)
    {
        var normalized = command with
        {
            Description = string.IsNullOrWhiteSpace(command.Description)
                ? null
                : command.Description.Trim(),
            AdjustmentReason = command.AdjustmentReason?.Trim() ?? string.Empty
        };
        var invalid = Validate(normalized);
        if (invalid is not null)
            return invalid;

        try
        {
            var revision = await reviewer.ReviewAsync(normalized, cancellationToken);
            return new(ReviewScrapOutcome.Reviewed, revision, null, null);
        }
        catch (ScrapRejectedException exception)
        {
            return new(
                ReviewScrapOutcome.Rejected,
                null,
                exception.ErrorCode,
                exception.Message);
        }
    }

    private static ReviewScrapResult? Validate(ReviewScrapCommand command)
    {
        if (command.ScrapId <= 0)
            return Invalid("SCRAP_ID_INVALID");
        if (command.OrderComponentId <= 0)
            return Invalid("ORDER_COMPONENT_ID_INVALID");
        if (command.ScrapReasonId <= 0)
            return Invalid("SCRAP_REASON_ID_INVALID");
        if (command.IsCancellation ? command.Quantity != 0 : command.Quantity <= 0)
            return Invalid("SCRAP_REVIEW_QUANTITY_INVALID");
        if (command.Description?.Length > MaximumDescriptionLength)
            return Invalid("SCRAP_DESCRIPTION_TOO_LONG");
        if (command.AdjustedBySupervisorId <= 0)
            return Invalid("ADJUSTED_BY_SUPERVISOR_ID_INVALID");
        if (command.AdjustmentReason.Length == 0)
            return Invalid("SCRAP_ADJUSTMENT_REASON_REQUIRED");
        if (command.AdjustmentReason.Length > MaximumAdjustmentReasonLength)
            return Invalid("SCRAP_ADJUSTMENT_REASON_TOO_LONG");
        if (command.CorrelationId == Guid.Empty)
            return Invalid("CORRELATION_ID_INVALID");
        return null;
    }

    private static ReviewScrapResult Invalid(string code) =>
        new(
            ReviewScrapOutcome.InvalidRequest,
            null,
            code,
            "La solicitud de revisión de scrap no es válida.");
}
