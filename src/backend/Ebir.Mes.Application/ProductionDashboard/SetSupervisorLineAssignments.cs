namespace Ebir.Mes.Application.ProductionDashboard;

public sealed class SetSupervisorLineAssignments(
    ILineSupervisorAssignmentWriter writer,
    IProductionDashboardReader reader)
{
    public const int MaxLines = 40;

    public async Task<IReadOnlyList<LineAssignmentOptionRecord>> ExecuteAsync(
        long supervisorEmployeeId,
        IReadOnlyCollection<long> lineIds,
        CancellationToken cancellationToken)
    {
        if (supervisorEmployeeId <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(supervisorEmployeeId));
        }

        var distinctLineIds = lineIds.Distinct().ToArray();
        if (distinctLineIds.Length > MaxLines || distinctLineIds.Any(id => id <= 0))
        {
            throw new ArgumentOutOfRangeException(nameof(lineIds));
        }

        await writer.SetAsync(supervisorEmployeeId, distinctLineIds, cancellationToken);
        return await reader.ReadLineAssignmentOptionsAsync(cancellationToken);
    }
}
