namespace Ebir.Mes.Application.Scrap;

public sealed class ScrapRejectedException : Exception
{
    public ScrapRejectedException(
        string errorCode,
        string message,
        Exception? innerException = null)
        : base(message, innerException) => ErrorCode = errorCode;

    public string ErrorCode { get; }
}
