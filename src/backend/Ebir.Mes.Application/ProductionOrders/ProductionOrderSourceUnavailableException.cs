namespace Ebir.Mes.Application.ProductionOrders;

public sealed class ProductionOrderSourceUnavailableException(
    string message,
    Exception? innerException = null)
    : Exception(message, innerException);
