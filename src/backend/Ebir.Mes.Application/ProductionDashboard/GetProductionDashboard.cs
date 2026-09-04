namespace Ebir.Mes.Application.ProductionDashboard;

public sealed class GetProductionDashboard(IProductionDashboardReader reader)
{
    public Task<ProductionDashboardSnapshotRecord> ExecuteAsync(
        CancellationToken cancellationToken) => reader.ReadAsync(cancellationToken);
}
