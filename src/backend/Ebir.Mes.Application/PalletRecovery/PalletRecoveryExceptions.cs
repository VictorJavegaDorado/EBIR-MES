namespace Ebir.Mes.Application.PalletRecovery;

public sealed class PalletRecoveryRejectedException(
    string code,
    string message,
    Exception? innerException = null) : Exception(message, innerException)
{
    public string Code { get; } = code;
}

public sealed class PalletRecoveryUnavailableException(
    string message,
    Exception? innerException = null) : Exception(message, innerException);
