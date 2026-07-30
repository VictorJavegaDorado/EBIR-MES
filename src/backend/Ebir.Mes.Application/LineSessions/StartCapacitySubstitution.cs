namespace Ebir.Mes.Application.LineSessions;

public sealed class StartCapacitySubstitution(ICapacitySubstitutionStarter starter)
{
    public const int MaximumReasonLength = 250;

    public async Task<StartCapacitySubstitutionResult> ExecuteAsync(
        StartCapacitySubstitutionCommand command,
        CancellationToken cancellationToken)
    {
        var normalizedReason = command.Reason?.Trim() ?? string.Empty;
        var validation = Validate(command, normalizedReason);
        if (validation is not null)
        {
            return validation;
        }

        try
        {
            var normalizedCommand = command with { Reason = normalizedReason };
            var substitution = await starter.StartAsync(
                normalizedCommand,
                cancellationToken);
            return new(
                StartCapacitySubstitutionOutcome.Started,
                substitution,
                null,
                null);
        }
        catch (LineSessionRejectedException exception)
        {
            return new(
                StartCapacitySubstitutionOutcome.Rejected,
                null,
                exception.ErrorCode,
                exception.Message);
        }
    }

    private static StartCapacitySubstitutionResult? Validate(
        StartCapacitySubstitutionCommand command,
        string normalizedReason)
    {
        if (command.LineSessionId <= 0)
            return Invalid("LINE_SESSION_ID_INVALID");
        if (command.ReplacedOperatorId <= 0)
            return Invalid("REPLACED_OPERATOR_ID_INVALID");
        if (command.SubstituteSupervisorId <= 0)
            return Invalid("SUBSTITUTE_SUPERVISOR_ID_INVALID");
        if (command.ReplacedOperatorId == command.SubstituteSupervisorId)
            return Invalid("SUBSTITUTION_EMPLOYEES_MUST_DIFFER");
        if (normalizedReason.Length == 0)
            return Invalid("SUBSTITUTION_REASON_REQUIRED");
        if (normalizedReason.Length > MaximumReasonLength)
            return Invalid("SUBSTITUTION_REASON_TOO_LONG");
        if (command.CorrelationId == Guid.Empty)
            return Invalid("CORRELATION_ID_INVALID");
        return null;
    }

    private static StartCapacitySubstitutionResult Invalid(string code) =>
        new(
            StartCapacitySubstitutionOutcome.InvalidRequest,
            null,
            code,
            "La solicitud de sustitución de capacidad no es válida.");
}
