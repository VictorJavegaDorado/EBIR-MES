namespace Ebir.Mes.Application.ProductionWorkstations;

public interface IProductionTableStarter
{
    Task<ProductionTableStartRecord> StartOrJoinAsync(
        StartOrJoinProductionTableCommand command,
        CancellationToken cancellationToken);
}
