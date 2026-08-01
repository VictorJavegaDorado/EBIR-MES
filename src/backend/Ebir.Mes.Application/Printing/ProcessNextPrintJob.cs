using System.Text.Json;

namespace Ebir.Mes.Application.Printing;

public sealed class ProcessNextPrintJob(IPrintJobQueue queue, IPrinter printer)
{
    public async Task<ProcessNextPrintJobResult> ExecuteAsync(
        string workerId,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(workerId);
        var job = await queue.ReserveNextAsync(workerId.Trim(), cancellationToken);
        if (job is null)
            return new(ProcessNextPrintJobOutcome.NoWork, null);

        try
        {
            var receipt = await printer.PrintAsync(job, cancellationToken);
            await queue.CompleteAsync(
                job,
                Guid.NewGuid(),
                receipt.TechnicalDataJson,
                cancellationToken);
            return new(ProcessNextPrintJobOutcome.Printed, job.PrintJobId);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (PrinterUnavailableException exception)
        {
            var technicalData = JsonSerializer.Serialize(new
            {
                adapter = printer.GetType().Name,
                exception = exception.GetType().Name
            });
            await queue.FailAsync(
                job,
                "PRINTER_UNAVAILABLE",
                technicalData,
                cancellationToken);
            return new(ProcessNextPrintJobOutcome.Failed, job.PrintJobId);
        }
    }
}
