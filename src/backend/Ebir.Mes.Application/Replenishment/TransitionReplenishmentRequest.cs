namespace Ebir.Mes.Application.Replenishment;

public sealed class TransitionReplenishmentRequest(
    IReplenishmentRequestTransitioner transitioner)
{
    public const int MaximumCommentLength = 500;

    private static readonly HashSet<string> AllowedStates =
    [
        "ACEPTADA",
        "EN_CAMINO",
        "ENTREGADA",
        "RECHAZADA",
        "CANCELADA"
    ];

    public async Task<TransitionReplenishmentRequestResult> ExecuteAsync(
        TransitionReplenishmentRequestCommand command,
        CancellationToken cancellationToken)
    {
        var normalized = command with
        {
            NewState = command.NewState?.Trim().ToUpperInvariant() ?? string.Empty,
            Comment = string.IsNullOrWhiteSpace(command.Comment)
                ? null
                : command.Comment.Trim()
        };
        var invalid = Validate(normalized);
        if (invalid is not null)
            return invalid;

        try
        {
            await transitioner.TransitionAsync(normalized, cancellationToken);
            return new(
                TransitionReplenishmentRequestOutcome.Transitioned,
                normalized.NewState,
                null,
                null);
        }
        catch (ReplenishmentRejectedException exception)
        {
            return new(
                TransitionReplenishmentRequestOutcome.Rejected,
                null,
                exception.ErrorCode,
                exception.Message);
        }
    }

    private static TransitionReplenishmentRequestResult? Validate(
        TransitionReplenishmentRequestCommand command)
    {
        if (command.RequestId <= 0)
            return Invalid("REPLENISHMENT_REQUEST_ID_INVALID");
        if (!AllowedStates.Contains(command.NewState))
            return Invalid("REPLENISHMENT_TARGET_STATE_INVALID");
        if (command.EmployeeId <= 0)
            return Invalid("REPLENISHMENT_EMPLOYEE_ID_INVALID");
        if (command.NewState is "RECHAZADA" or "CANCELADA"
            && command.Comment is null)
            return Invalid("REPLENISHMENT_TRANSITION_COMMENT_REQUIRED");
        if (command.Comment?.Length > MaximumCommentLength)
            return Invalid("REPLENISHMENT_TRANSITION_COMMENT_TOO_LONG");
        if (command.CorrelationId == Guid.Empty)
            return Invalid("CORRELATION_ID_INVALID");
        return null;
    }

    private static TransitionReplenishmentRequestResult Invalid(string code) =>
        new(
            TransitionReplenishmentRequestOutcome.InvalidRequest,
            null,
            code,
            "La transición de reaprovisionamiento no es válida.");
}
