namespace Ebir.Mes.Application.Pallets.ClosePallet;

public sealed class ClosePallet(IPalletCloser closer)
{
    private static readonly HashSet<string> AllowedPartialReasons =
    ["FIN_TURNO", "FALTA_MATERIAL", "ULTIMO_PALET"];

    public async Task<ClosePalletResult> ExecuteAsync(
        ClosePalletCommand command,
        CancellationToken cancellationToken)
    {
        var reason = string.IsNullOrWhiteSpace(command.PartialReason)
            ? null : command.PartialReason.Trim().ToUpperInvariant();
        var normalized = command with { PartialReason = reason };
        var invalid = Validate(normalized);
        if (invalid is not null) return invalid;
        try
        {
            var pallet = await closer.CloseAsync(normalized, cancellationToken);
            return new(ClosePalletOutcome.Closed, pallet, null, null);
        }
        catch (PalletCloseRejectedException exception)
        {
            return new(ClosePalletOutcome.Rejected, null, exception.ErrorCode, exception.Message);
        }
    }

    private static ClosePalletResult? Validate(ClosePalletCommand command)
    {
        if (command.ReservationId <= 0) return Invalid("PALLET_RESERVATION_ID_INVALID");
        if (command.GoodQuantity <= 0) return Invalid("PALLET_GOOD_QUANTITY_INVALID");
        if (command.ClosedByEmployeeId <= 0) return Invalid("PALLET_CLOSER_ID_INVALID");
        if (command.AuthorizingSupervisorId is <= 0) return Invalid("PALLET_SUPERVISOR_ID_INVALID");
        if (command.CorrelationId == Guid.Empty) return Invalid("CORRELATION_ID_INVALID");
        if (!command.IsPartial && command.PartialReason is not null) return Invalid("PALLET_PARTIAL_REASON_NOT_ALLOWED");
        if (command.IsPartial && command.PartialReason is null) return Invalid("PALLET_PARTIAL_REASON_REQUIRED");
        if (command.IsPartial && !AllowedPartialReasons.Contains(command.PartialReason!)) return Invalid("PALLET_PARTIAL_REASON_INVALID");
        return null;
    }

    private static ClosePalletResult Invalid(string code) =>
        new(ClosePalletOutcome.InvalidRequest, null, code, "La solicitud de cierre de palé no es válida.");
}
