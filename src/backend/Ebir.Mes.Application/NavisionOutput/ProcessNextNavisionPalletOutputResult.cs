namespace Ebir.Mes.Application.NavisionOutput;

public sealed record ProcessNextNavisionPalletOutputResult(
    ProcessNextNavisionPalletOutputOutcome Outcome,
    long? OperationId);
