namespace Ebir.Mes.Application.Printing;

public sealed class PalletLabelReprintRejectedException(
    string errorCode,
    string message,
    Exception? innerException = null) : Exception(message, innerException)
{
    public string ErrorCode { get; } = errorCode;
}
