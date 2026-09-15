namespace Ebir.Mes.Application.ProductionDashboard;

public interface ILineSupervisorAssignmentWriter
{
    Task SetAsync(
        long supervisorEmployeeId,
        IReadOnlyCollection<long> lineIds,
        CancellationToken cancellationToken);
}
