namespace Ebir.Mes.Application.NavisionOutput;

public sealed record NavisionPalletOutputJob(
    long OperationId,
    Guid OperationUid,
    string IdempotencyKey,
    string OrderNumber,
    string ProductNumber,
    int GoodQuantity,
    DateTimeOffset ClosedAtUtc,
    int AttemptNumber);
