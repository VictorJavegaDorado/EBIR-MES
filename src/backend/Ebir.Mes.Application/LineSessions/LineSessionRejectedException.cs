namespace Ebir.Mes.Application.LineSessions;

public sealed class LineSessionRejectedException(
    string errorCode,
    string safeMessage,
    Exception? innerException = null)
    : Exception(safeMessage, innerException)
{
    public string ErrorCode { get; } = errorCode;
}
