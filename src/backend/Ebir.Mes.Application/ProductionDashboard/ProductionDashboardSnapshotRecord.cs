using Ebir.Mes.Application.ProductionOrders;
using Ebir.Mes.Application.ProductionWorkstations;

namespace Ebir.Mes.Application.ProductionDashboard;

public sealed record ProductionDashboardSnapshotRecord(
    DateTime ServerTimeUtc,
    IReadOnlyList<ProductionDashboardLineRecord> Lines);

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
    int PrintIssues);
