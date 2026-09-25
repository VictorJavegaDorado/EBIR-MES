namespace Ebir.Mes.Application.Replenishment;

public sealed record MaterialRequestTrackingRecord(
    long RequestId,
    Guid CorrelationId,
    string ComponentCode,
    string Description,
    int Quantity,
    DateTime RequestedAtUtc);

public interface IMaterialRequestTrackingReader
{
    Task<IReadOnlyList<MaterialRequestTrackingRecord>> ReadAsync(
        long lineSessionId,
        CancellationToken cancellationToken);
}

public sealed record NavMaterialRequestStatus(
    int RequestId,
    int PickingStatusCode,
    string PickingStatusText,
    string? PickingNumber,
    DateTime? RegisteredAt,
    string? Error);

public interface INavisionMaterialRequestStatusReader
{
    Task<NavMaterialRequestStatus?> ReadAsync(
        Guid correlationId,
        CancellationToken cancellationToken);
}

public sealed record ProductionMaterialRequestStatus(
    long Id,
    int NavRequestId,
    Guid CorrelationId,
    string ComponentCode,
    string Description,
    int Quantity,
    DateTime RequestedAtUtc,
    string State,
    string NavState,
    string? PickingNumber,
    DateTime? RegisteredAt,
    string? Error);

public sealed class GetProductionMaterialRequestStatuses(
    IMaterialRequestTrackingReader trackingReader,
    INavisionMaterialRequestStatusReader navision)
{
    public async Task<IReadOnlyList<ProductionMaterialRequestStatus>> ExecuteAsync(
        long lineSessionId,
        CancellationToken cancellationToken)
    {
        if (lineSessionId <= 0)
            return [];

        var tracked = await trackingReader.ReadAsync(lineSessionId, cancellationToken);
        var result = new List<ProductionMaterialRequestStatus>(tracked.Count);
        foreach (var request in tracked)
        {
            var navStatus = await navision.ReadAsync(request.CorrelationId, cancellationToken);
            if (navStatus is null)
            {
                result.Add(new(
                    request.RequestId,
                    0,
                    request.CorrelationId,
                    request.ComponentCode,
                    request.Description,
                    request.Quantity,
                    request.RequestedAtUtc,
                    "PENDING",
                    "Pendiente de sincronizar",
                    null,
                    null,
                    null));
                continue;
            }

            result.Add(new(
                request.RequestId,
                navStatus.RequestId,
                request.CorrelationId,
                request.ComponentCode,
                request.Description,
                request.Quantity,
                request.RequestedAtUtc,
                ToState(navStatus.PickingStatusCode),
                navStatus.PickingStatusText,
                navStatus.PickingNumber,
                navStatus.RegisteredAt,
                navStatus.Error));
        }
        return result;
    }

    public static string ToState(int pickingStatusCode) => pickingStatusCode switch
    {
        0 => "PENDING",
        2 or 3 => "PREPARING",
        1 or 4 or 5 => "SENT",
        6 or 7 or 8 => "ERROR",
        _ => "ERROR"
    };
}
