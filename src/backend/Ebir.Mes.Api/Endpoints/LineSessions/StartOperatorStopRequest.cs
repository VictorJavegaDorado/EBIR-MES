namespace Ebir.Mes.Api.Endpoints.LineSessions;

public sealed record StartOperatorStopRequest(
    long EmployeeId, string Reason, Guid CorrelationId);
