namespace Ebir.Mes.Application.ProductionDashboard;

public sealed record LineAssignmentOptionRecord(
    long LineId,
    string LineCode,
    string LineName,
    string WorkCenterCode,
    string WorkCenterName,
    string? SupervisorNavEmployeeCode,
    string? SupervisorName);
