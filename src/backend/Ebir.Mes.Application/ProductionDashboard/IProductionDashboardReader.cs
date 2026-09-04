namespace Ebir.Mes.Application.ProductionDashboard;

public interface IProductionDashboardReader
{
    Task<ProductionDashboardSnapshotRecord> ReadAsync(
        CancellationToken cancellationToken);
}
