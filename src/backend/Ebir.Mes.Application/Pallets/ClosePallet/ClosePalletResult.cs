namespace Ebir.Mes.Application.Pallets.ClosePallet;

public sealed record ClosePalletResult(
    ClosePalletOutcome Outcome,
    ClosedPalletRecord? Pallet,
    string? ErrorCode,
    string? ErrorMessage);
