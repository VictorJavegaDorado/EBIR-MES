using Ebir.Mes.Application.Printing;
using Xunit;

namespace Ebir.Mes.Application.Tests.Printing;

public sealed class ProcessNextPrintJobTests
{
    [Fact]
    public async Task ExecuteAsync_returns_no_work_for_empty_queue()
    {
        var queue = new StubQueue(null);
        var result = await new ProcessNextPrintJob(queue, new StubPrinter())
            .ExecuteAsync("worker-1", CancellationToken.None);

        Assert.Equal(ProcessNextPrintJobOutcome.NoWork, result.Outcome);
        Assert.Null(result.PrintJobId);
    }

    [Fact]
    public async Task ExecuteAsync_prints_and_completes_reserved_job()
    {
        var queue = new StubQueue(Job);
        var result = await new ProcessNextPrintJob(queue, new StubPrinter())
            .ExecuteAsync("worker-1", CancellationToken.None);

        Assert.Equal(ProcessNextPrintJobOutcome.Printed, result.Outcome);
        Assert.Equal(Job.PrintJobId, queue.Completed?.PrintJobId);
        Assert.Null(queue.Failed);
    }

    [Fact]
    public async Task ExecuteAsync_records_normalized_adapter_failure()
    {
        var queue = new StubQueue(Job);
        var result = await new ProcessNextPrintJob(
            queue,
            new StubPrinter(shouldFail: true))
            .ExecuteAsync("worker-1", CancellationToken.None);

        Assert.Equal(ProcessNextPrintJobOutcome.Failed, result.Outcome);
        Assert.Equal("PRINTER_UNAVAILABLE", queue.FailureCode);
        Assert.Null(queue.Completed);
    }

    private static readonly PrintJobRecord Job = new(
        7, Guid.NewGuid(), 8, Guid.NewGuid(), 9, "SIM-01", "SIMULADA",
        "PALET", 1, "{}", 1, 1);

    private sealed class StubPrinter(bool shouldFail = false) : IPrinter
    {
        public Task<PrintReceipt> PrintAsync(
            PrintJobRecord job,
            CancellationToken cancellationToken) =>
            shouldFail
                ? throw new PrinterUnavailableException("Synthetic failure")
                : Task.FromResult(new PrintReceipt("{\"simulated\":true}"));
    }

    private sealed class StubQueue(PrintJobRecord? job) : IPrintJobQueue
    {
        public PrintJobRecord? Completed { get; private set; }
        public PrintJobRecord? Failed { get; private set; }
        public string? FailureCode { get; private set; }

        public Task<PrintJobRecord?> ReserveNextAsync(
            string workerId,
            CancellationToken cancellationToken) => Task.FromResult(job);

        public Task CompleteAsync(
            PrintJobRecord printJob,
            Guid correlationId,
            string technicalDataJson,
            CancellationToken cancellationToken)
        {
            Completed = printJob;
            return Task.CompletedTask;
        }

        public Task FailAsync(
            PrintJobRecord printJob,
            string normalizedError,
            string technicalDataJson,
            CancellationToken cancellationToken)
        {
            Failed = printJob;
            FailureCode = normalizedError;
            return Task.CompletedTask;
        }
    }
}
