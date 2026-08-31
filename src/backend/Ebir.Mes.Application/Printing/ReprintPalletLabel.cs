namespace Ebir.Mes.Application.Printing;

public sealed class ReprintPalletLabel(IPalletLabelReprinter reprinter)
{
    public const int MaximumReasonLength = 500;

    public async Task<ReprintPalletLabelResult> ExecuteAsync(
        ReprintPalletLabelCommand command,
        CancellationToken cancellationToken)
    {
        var normalized = command with
        {
            Reason = command.Reason?.Trim() ?? string.Empty
        };
        var invalid = Validate(normalized);
        if (invalid is not null)
            return invalid;

        try
        {
            var reprint = await reprinter.ReprintAsync(normalized, cancellationToken);
            return new(ReprintPalletLabelOutcome.Queued, reprint, null, null);
        }
        catch (PalletLabelReprintRejectedException exception)
        {
            return new(
                ReprintPalletLabelOutcome.Rejected,
                null,
                exception.ErrorCode,
                exception.Message);
        }
    }

    private static ReprintPalletLabelResult? Validate(
        ReprintPalletLabelCommand command)
    {
        if (command.PalletId <= 0)
            return Invalid("PALLET_ID_INVALID");
        if (command.RequestedBySupervisorId <= 0)
            return Invalid("REPRINT_SUPERVISOR_ID_INVALID");
        if (command.Reason.Length == 0)
            return Invalid("REPRINT_REASON_REQUIRED");
        if (command.Reason.Length > MaximumReasonLength)
            return Invalid("REPRINT_REASON_TOO_LONG");
        if (command.CorrelationId == Guid.Empty)
            return Invalid("CORRELATION_ID_INVALID");
        return null;
    }

    private static ReprintPalletLabelResult Invalid(string code) =>
        new(
            ReprintPalletLabelOutcome.InvalidRequest,
            null,
            code,
            "La solicitud de reimpresión no es válida.");
}
