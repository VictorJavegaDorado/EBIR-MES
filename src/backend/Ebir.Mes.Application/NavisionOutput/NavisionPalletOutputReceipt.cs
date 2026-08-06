namespace Ebir.Mes.Application.NavisionOutput;

public sealed record NavisionPalletOutputReceipt(
    NavisionPalletOutputDeliveryOutcome Outcome,
    string? ExternalIdentifier,
    int? HttpStatusCode,
    string TechnicalDataJson);
