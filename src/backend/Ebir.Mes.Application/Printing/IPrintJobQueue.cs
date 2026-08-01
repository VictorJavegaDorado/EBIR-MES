namespace Ebir.Mes.Application.Printing;

public interface IPrintJobQueue
{
    Task<PrintJobRecord?> ReserveNextAsync(
        string workerId,
        CancellationToken cancellationToken);

    Task CompleteAsync(
        PrintJobRecord job,
        Guid correlationId,
        string technicalDataJson,
        CancellationToken cancellationToken);

    Task FailAsync(
        PrintJobRecord job,
        string normalizedError,
        string technicalDataJson,
        CancellationToken cancellationToken);
}
