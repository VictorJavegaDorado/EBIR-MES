namespace Ebir.Mes.Application.ProductionDashboard;

public sealed class LineSupervisorAssignmentRejectedException(string code, string message)
    : Exception(message)
{
    public string Code { get; } = code;
}
