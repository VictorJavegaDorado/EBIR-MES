namespace Ebir.Mes.Application.ProductionWorkstations;

public sealed class ProductionTableRejectedException(
    string errorCode,
    string message,
    Exception? innerException = null) : Exception(message, innerException)
{
    public string ErrorCode { get; } = errorCode;
}
