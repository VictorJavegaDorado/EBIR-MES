namespace Ebir.Mes.Application.Printing;

public sealed record ReprintPalletLabelResult(
    ReprintPalletLabelOutcome Outcome,
    ReprintedPalletLabelRecord? Reprint,
    string? ErrorCode,
    string? ErrorMessage);
