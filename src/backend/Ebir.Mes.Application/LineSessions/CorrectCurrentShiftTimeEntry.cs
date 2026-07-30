namespace Ebir.Mes.Application.LineSessions;

public sealed class CorrectCurrentShiftTimeEntry(
    ICurrentShiftTimeEntryCorrector corrector)
{
    public const int MaximumReasonLength = 500;

    public async Task<CorrectCurrentShiftTimeEntryResult> ExecuteAsync(
        CorrectCurrentShiftTimeEntryCommand command,
        CancellationToken cancellationToken)
    {
        var reason = command.Reason?.Trim() ?? string.Empty;
        var normalized = command with
        {
            CorrectedEntryUtc = command.CorrectedEntryUtc.ToUniversalTime(),
            CorrectedExitUtc = command.CorrectedExitUtc?.ToUniversalTime(),
            Reason = reason
        };
        var invalid = Validate(normalized);
        if (invalid is not null)
            return invalid;

        try
        {
            await corrector.CorrectAsync(normalized, cancellationToken);
            return new(CorrectCurrentShiftTimeEntryOutcome.Corrected, null, null);
        }
        catch (LineSessionRejectedException exception)
        {
            return new(
                CorrectCurrentShiftTimeEntryOutcome.Rejected,
                exception.ErrorCode,
                exception.Message);
        }
    }

    private static CorrectCurrentShiftTimeEntryResult? Validate(
        CorrectCurrentShiftTimeEntryCommand command)
    {
        if (command.TimeEntryId <= 0)
            return Invalid("TIME_ENTRY_ID_INVALID");
        if (command.CorrectedEntryUtc == default)
            return Invalid("CORRECTED_ENTRY_UTC_REQUIRED");
        if (command.CorrectedExitUtc < command.CorrectedEntryUtc)
            return Invalid("CORRECTED_EXIT_BEFORE_ENTRY");
        if (command.SupervisorId <= 0)
            return Invalid("SUPERVISOR_ID_INVALID");
        if (command.Reason.Length == 0)
            return Invalid("TIME_ENTRY_CORRECTION_REASON_REQUIRED");
        if (command.Reason.Length > MaximumReasonLength)
            return Invalid("TIME_ENTRY_CORRECTION_REASON_TOO_LONG");
        if (command.CorrelationId == Guid.Empty)
            return Invalid("CORRELATION_ID_INVALID");
        return null;
    }

    private static CorrectCurrentShiftTimeEntryResult Invalid(string code) =>
        new(
            CorrectCurrentShiftTimeEntryOutcome.InvalidRequest,
            code,
            "La solicitud de corrección de fichaje no es válida.");
}
