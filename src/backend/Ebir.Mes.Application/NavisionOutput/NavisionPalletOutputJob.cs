namespace Ebir.Mes.Application.NavisionOutput;

public sealed record NavisionPalletOutputJob(
    long OperationId,
    Guid OperationUid,
    string IdempotencyKey,
    string OrderNumber,
    string ProductNumber,
    string LotNumber,
    string EmployeeNumber,
    string LineCode,
    int GoodQuantity,
    DateTimeOffset ClosedAtUtc,
    int AttemptNumber,
    string? ExternalIdentifier,
    bool ReconciliationOnly = false,
    int? BaselineMaximumId = null);
