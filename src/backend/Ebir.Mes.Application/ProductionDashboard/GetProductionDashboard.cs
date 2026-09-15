namespace Ebir.Mes.Application.ProductionDashboard;

public sealed class GetProductionDashboard(IProductionDashboardReader reader)
{
    public const int MaxSupervisorCodeLength = 30;

    public Task<ProductionDashboardSnapshotRecord> ExecuteAsync(
        string? supervisorNavEmployeeCode,
        CancellationToken cancellationToken)
    {
        var code = supervisorNavEmployeeCode?.Trim();
        if (code is { Length: > MaxSupervisorCodeLength })
        {
            throw new ArgumentOutOfRangeException(nameof(supervisorNavEmployeeCode));
        }

        return reader.ReadAsync(string.IsNullOrEmpty(code) ? null : code, cancellationToken);
    }

    public Task<IReadOnlyList<ProductionDashboardSupervisorRecord>> ListSupervisorsAsync(
        CancellationToken cancellationToken) => reader.ReadSupervisorsAsync(cancellationToken);

    public Task<IReadOnlyList<LineAssignmentOptionRecord>> ListLineAssignmentOptionsAsync(
        CancellationToken cancellationToken) => reader.ReadLineAssignmentOptionsAsync(cancellationToken);
}
