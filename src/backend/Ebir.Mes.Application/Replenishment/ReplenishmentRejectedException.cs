namespace Ebir.Mes.Application.Replenishment;

public sealed class ReplenishmentRejectedException : Exception
{
    public ReplenishmentRejectedException(
        string errorCode,
        string message,
        Exception? innerException = null)
        : base(message, innerException) => ErrorCode = errorCode;

    public string ErrorCode { get; }
}
