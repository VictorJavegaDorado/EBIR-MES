using Ebir.Mes.Application.NavisionOutput;
using Xunit;

namespace Ebir.Mes.Application.Tests.NavisionOutput;

public sealed class ProcessNextNavisionPalletOutputTests
{
    [Fact]
    public async Task ExecuteAsync_returns_no_work_for_empty_queue()
    {
        var queue = new StubQueue(null);
        var result = await new ProcessNextNavisionPalletOutput(queue, new StubSender(Confirmed))
            .ExecuteAsync(" worker-1 ", CancellationToken.None);

        Assert.Equal(ProcessNextNavisionPalletOutputOutcome.NoWork, result.Outcome);
        Assert.Equal("worker-1", queue.WorkerId);
    }

    [Fact]
    public async Task ExecuteAsync_sends_and_completes_confirmed_output()
    {
        var queue = new StubQueue(Job);
        var result = await new ProcessNextNavisionPalletOutput(queue, new StubSender(Confirmed))
            .ExecuteAsync("worker-1", CancellationToken.None);

        Assert.Equal(ProcessNextNavisionPalletOutputOutcome.Confirmed, result.Outcome);
        Assert.Equal(Job.OperationId, queue.Completed?.OperationId);
        Assert.Null(queue.Failed);
    }

    [Theory]
    [InlineData(NavisionPalletOutputDeliveryOutcome.RetryableFailure,
        ProcessNextNavisionPalletOutputOutcome.Failed)]
    [InlineData(NavisionPalletOutputDeliveryOutcome.PermanentFailure,
        ProcessNextNavisionPalletOutputOutcome.Failed)]
    [InlineData(NavisionPalletOutputDeliveryOutcome.UnknownResult,
        ProcessNextNavisionPalletOutputOutcome.UnknownResult)]
    public async Task ExecuteAsync_persists_non_confirmed_outcome(
        NavisionPalletOutputDeliveryOutcome delivery,
        ProcessNextNavisionPalletOutputOutcome expected)
    {
        var queue = new StubQueue(Job);
        var receipt = new NavisionPalletOutputReceipt(delivery, null, 503, "{}");
        var result = await new ProcessNextNavisionPalletOutput(queue, new StubSender(receipt))
            .ExecuteAsync("worker-1", CancellationToken.None);

        Assert.Equal(expected, result.Outcome);
        Assert.Equal(delivery, queue.Failed?.Outcome);
        Assert.Null(queue.Completed);
    }

    [Fact]
    public async Task ExecuteAsync_marks_unknown_confirmation_without_external_identifier()
    {
        var queue = new StubQueue(Job);
        var receipt = Confirmed with { ExternalIdentifier = null };

        var result = await new ProcessNextNavisionPalletOutput(queue, new StubSender(receipt))
            .ExecuteAsync("worker-1", CancellationToken.None);

        Assert.Equal(ProcessNextNavisionPalletOutputOutcome.UnknownResult, result.Outcome);
        Assert.Null(queue.Completed);
        Assert.Equal(
            NavisionPalletOutputDeliveryOutcome.UnknownResult,
            queue.Failed?.Outcome);
    }

    private static readonly NavisionPalletOutputJob Job = new(
        7,
        Guid.NewGuid(),
        "MES:PALET:synthetic",
        "FL-TEST",
        "ITEM-TEST",
        "LOT-TEST",
        "EMP-TEST",
        "LINE-TEST",
        20,
        new DateTimeOffset(2026, 8, 6, 10, 30, 0, TimeSpan.Zero),
        1);

    private static readonly NavisionPalletOutputReceipt Confirmed = new(
        NavisionPalletOutputDeliveryOutcome.Confirmed,
        "NAV-TEST-1",
        200,
        "{\"adapter\":\"stub\"}");

    private sealed class StubSender(NavisionPalletOutputReceipt receipt)
        : INavisionPalletOutputSender
    {
        public Task<NavisionPalletOutputReceipt> SendAsync(
            NavisionPalletOutputJob job,
            CancellationToken cancellationToken) => Task.FromResult(receipt);
    }

    private sealed class StubQueue(NavisionPalletOutputJob? job)
        : INavisionPalletOutputQueue
    {
        public string? WorkerId { get; private set; }
        public NavisionPalletOutputJob? Completed { get; private set; }
        public NavisionPalletOutputReceipt? Failed { get; private set; }

        public Task<NavisionPalletOutputJob?> ReserveNextAsync(
            string workerId,
            CancellationToken cancellationToken)
        {
            WorkerId = workerId;
            return Task.FromResult(job);
        }

        public Task CompleteAsync(
            NavisionPalletOutputJob output,
            NavisionPalletOutputReceipt receipt,
            Guid correlationId,
            CancellationToken cancellationToken)
        {
            Completed = output;
            return Task.CompletedTask;
        }

        public Task FailAsync(
            NavisionPalletOutputJob output,
            NavisionPalletOutputReceipt receipt,
            CancellationToken cancellationToken)
        {
            Failed = receipt;
            return Task.CompletedTask;
        }
    }
}
