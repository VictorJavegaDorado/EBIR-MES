namespace Ebir.Mes.Api.Endpoints.LineSessions;

public sealed record RegisterProductiveEntryRequest(
    long EmployeeId,
    Guid CorrelationId);
