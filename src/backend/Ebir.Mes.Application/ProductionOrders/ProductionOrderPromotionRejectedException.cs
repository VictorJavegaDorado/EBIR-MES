namespace Ebir.Mes.Application.ProductionOrders;

public sealed class ProductionOrderPromotionRejectedException(
    string code,
    string message,
    Exception? innerException = null) : Exception(message, innerException)
{
    public string Code { get; } = code;
}
