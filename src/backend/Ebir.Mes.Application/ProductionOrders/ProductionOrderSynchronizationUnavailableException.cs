namespace Ebir.Mes.Application.ProductionOrders;

public sealed class ProductionOrderSynchronizationUnavailableException(
    string message,
    Exception? innerException = null)
    : Exception(message, innerException);
