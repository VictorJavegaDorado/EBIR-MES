using Ebir.Mes.Application.ProductionOrders;
using Ebir.Mes.Application.ProductionWorkstations;

namespace Ebir.Mes.Application.ProductionDashboard;

public sealed record ProductionDashboardSnapshotRecord(
    DateTime ServerTimeUtc,
    IReadOnlyList<ProductionDashboardLineRecord> Lines,
    ProductionDashboardSupervisorRecord? Supervisor = null);

public sealed record ProductionDashboardLineRecord(
    long LineId,
    string LineCode,
    string LineName,
    string WorkCenterCode,
    string WorkCenterName,
    string OperationalState,
    string? BlockReason,
    DateTime? UpdatedAtUtc,
    ProductionOrderSelectionRecord? Order,
    ProductionTableStateRecord? Table,
    int ClosedPallets,
    string? LatestNavState,
    string? LatestLabelState,
    int PendingNavOutputs,
    int NavIssues,
    int PendingPrintJobs,
    int PrintIssues,
    decimal TheoreticalUnitsToDate,
    long ResourceSeconds = 0,
    string? SupervisorNavEmployeeCode = null,
    string? SupervisorName = null);

public sealed record ProductionDashboardSupervisorRecord(
    string NavEmployeeCode,
    string FullName,
    IReadOnlyList<ProductionDashboardSupervisorLineRecord> Lines);

public sealed record ProductionDashboardSupervisorLineRecord(
    long LineId,
    string LineCode,
    string LineName);
