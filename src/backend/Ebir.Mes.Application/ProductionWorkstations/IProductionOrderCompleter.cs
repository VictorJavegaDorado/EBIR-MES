namespace Ebir.Mes.Application.ProductionWorkstations;

public interface IProductionOrderCompleter
{
    Task CompleteAsync(
        CompleteProductionOrderCommand command,
        CancellationToken cancellationToken);
}
