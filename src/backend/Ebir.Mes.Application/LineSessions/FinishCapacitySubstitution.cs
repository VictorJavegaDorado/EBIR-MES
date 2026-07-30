namespace Ebir.Mes.Application.LineSessions;

public sealed class FinishCapacitySubstitution(ICapacitySubstitutionFinisher finisher)
{
    public const int MaximumReasonLength = 250;

    public async Task<FinishCapacitySubstitutionResult> ExecuteAsync(
        FinishCapacitySubstitutionCommand command,
        CancellationToken cancellationToken)
    {
        var reason = command.Reason?.Trim() ?? string.Empty;
        var invalid = Validate(command, reason);
        if (invalid is not null)
        {
            return invalid;
        }

        try
        {
            var activeResources = await finisher.FinishAsync(
                command with { Reason = reason },
                cancellationToken);
            return new(
                FinishCapacitySubstitutionOutcome.Finished,
                activeResources,
                null,
                null);
        }
        catch (LineSessionRejectedException exception)
        {
            return new(
                FinishCapacitySubstitutionOutcome.Rejected,
                null,
                exception.ErrorCode,
                exception.Message);
        }
    }

    private static FinishCapacitySubstitutionResult? Validate(
        FinishCapacitySubstitutionCommand command,
        string reason)
    {
        if (command.CapacitySubstitutionId <= 0)
            return Invalid("CAPACITY_SUBSTITUTION_ID_INVALID");
        if (command.SupervisorId <= 0)
            return Invalid("SUPERVISOR_ID_INVALID");
        if (reason.Length == 0)
            return Invalid("SUBSTITUTION_FINISH_REASON_REQUIRED");
        if (reason.Length > MaximumReasonLength)
            return Invalid("SUBSTITUTION_FINISH_REASON_TOO_LONG");
        if (command.CorrelationId == Guid.Empty)
            return Invalid("CORRELATION_ID_INVALID");
        return null;
    }

    private static FinishCapacitySubstitutionResult Invalid(string code) =>
        new(
            FinishCapacitySubstitutionOutcome.InvalidRequest,
            null,
            code,
            "La solicitud de finalización de sustitución no es válida.");
}
