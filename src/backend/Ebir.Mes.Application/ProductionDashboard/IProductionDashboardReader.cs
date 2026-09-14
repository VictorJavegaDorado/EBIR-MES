namespace Ebir.Mes.Application.ProductionDashboard;

public interface IProductionDashboardReader
{
    Task<ProductionDashboardSnapshotRecord> ReadAsync(
        string? supervisorNavEmployeeCode,
        CancellationToken cancellationToken);

    Task<IReadOnlyList<ProductionDashboardSupervisorRecord>> ReadSupervisorsAsync(
        CancellationToken cancellationToken);
}
