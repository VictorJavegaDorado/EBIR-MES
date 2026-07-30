namespace Ebir.Mes.Application.Pallets.ClosePallet;

public sealed class PalletCloseUnavailableException(
    string message,
    Exception? innerException = null) : Exception(message, innerException);
