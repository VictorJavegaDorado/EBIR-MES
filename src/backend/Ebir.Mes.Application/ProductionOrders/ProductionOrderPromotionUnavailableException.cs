namespace Ebir.Mes.Application.ProductionOrders;

public sealed class ProductionOrderPromotionUnavailableException(
    string message,
    Exception? innerException = null) : Exception(message, innerException);
