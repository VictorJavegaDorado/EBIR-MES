namespace Ebir.Mes.Application.ProductionOrders;

public sealed class ProductionOrderPreparationRejectedException(
    string code,
    string message) : Exception(message)
{
    public string Code { get; } = code;
}
