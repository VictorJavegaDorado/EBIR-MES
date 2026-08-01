namespace Ebir.Mes.Application.ProductionOrders;

public sealed class ProductionOrderSelectionUnavailableException(
    string message,
    Exception? innerException = null)
    : Exception(message, innerException);
