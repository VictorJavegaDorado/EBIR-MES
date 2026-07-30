namespace Ebir.Mes.Application.Pallets.ClosePallet;

public sealed class PalletCloseRejectedException(
    string errorCode,
    string message,
    Exception? innerException = null) : Exception(message, innerException)
{
    public string ErrorCode { get; } = errorCode;
}
