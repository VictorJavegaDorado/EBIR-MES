namespace Ebir.Mes.Application.Printing.LabelControl;

public sealed record LabelControlSnapshotRecord(
    DateTime ServerTimeUtc,
    IReadOnlyList<LabelControlOrderRecord> Orders);

public sealed record LabelControlOrderRecord(
    long OrderId,
    string OrderNumber,
    string ProductNumber,
    string ProductDescription,
    string OrderState,
    long LineId,
    string LineCode,
    string LineName,
    DateTime LastPalletClosedAtUtc,
    IReadOnlyList<LabelControlPalletRecord> Pallets);

public sealed record LabelControlPalletRecord(
    long PalletId,
    int PalletNumber,
    decimal GoodQuantity,
    bool IsLast,
    DateTime ClosedAtUtc,
    long? NavOperationId,
    string? NavState,
    long? LabelId,
    string? LabelState,
    long? PrintJobId,
    string? PrintState,
    int PrintAttempts,
    bool HasIncident,
    bool CanReprint);
