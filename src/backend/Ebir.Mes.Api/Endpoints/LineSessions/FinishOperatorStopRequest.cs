namespace Ebir.Mes.Api.Endpoints.LineSessions;

public sealed record FinishOperatorStopRequest(long EmployeeId, Guid CorrelationId);
