namespace Ebir.Mes.Api.Endpoints.LineSessions;

public sealed record RegisterProductiveExitRequest(
    long EmployeeId,
    Guid CorrelationId);
