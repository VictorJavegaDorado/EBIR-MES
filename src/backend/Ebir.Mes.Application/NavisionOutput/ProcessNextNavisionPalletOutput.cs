namespace Ebir.Mes.Application.NavisionOutput;

public sealed class ProcessNextNavisionPalletOutput(
    INavisionPalletOutputQueue queue,
    INavisionPalletOutputSender sender)
{
    public async Task<ProcessNextNavisionPalletOutputResult> ExecuteAsync(
        string workerId,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(workerId);
        var job = await queue.ReserveNextAsync(workerId.Trim(), cancellationToken);
        if (job is null)
            return new(ProcessNextNavisionPalletOutputOutcome.NoWork, null);

        var receipt = await sender.SendAsync(job, cancellationToken);
        if (receipt.Outcome == NavisionPalletOutputDeliveryOutcome.Confirmed)
        {
            if (string.IsNullOrWhiteSpace(receipt.ExternalIdentifier))
            {
                await queue.FailAsync(
                    job,
                    receipt with
                    {
                        Outcome = NavisionPalletOutputDeliveryOutcome.UnknownResult
                    },
                    cancellationToken);
                return new(
                    ProcessNextNavisionPalletOutputOutcome.UnknownResult,
                    job.OperationId);
            }

            await queue.CompleteAsync(
                job,
                receipt,
                Guid.NewGuid(),
                cancellationToken);
            return new(ProcessNextNavisionPalletOutputOutcome.Confirmed, job.OperationId);
        }

        await queue.FailAsync(job, receipt, cancellationToken);
        return new(
            receipt.Outcome == NavisionPalletOutputDeliveryOutcome.UnknownResult
                ? ProcessNextNavisionPalletOutputOutcome.UnknownResult
                : ProcessNextNavisionPalletOutputOutcome.Failed,
            job.OperationId);
    }
}
