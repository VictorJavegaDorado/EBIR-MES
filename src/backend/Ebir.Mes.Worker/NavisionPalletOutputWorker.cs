using Ebir.Mes.Application.NavisionOutput;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Ebir.Mes.Worker;

public sealed class NavisionPalletOutputWorker(
    ProcessNextNavisionPalletOutput processor,
    IConfiguration configuration,
    IHostApplicationLifetime lifetime,
    ILogger<NavisionPalletOutputWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var workerId = $"{Environment.MachineName}:{Environment.ProcessId}:NAV_PALLET";
        var pollInterval = TimeSpan.FromMilliseconds(
            Math.Clamp(
                configuration.GetValue("NavisionOutput:PollIntervalMilliseconds", 1000),
                100,
                60000));
        var runOnce = configuration.GetValue<bool>("NavisionOutput:RunOnce");

        do
        {
            try
            {
                var result = await processor.ExecuteAsync(workerId, stoppingToken);
                if (result.Outcome == ProcessNextNavisionPalletOutputOutcome.NoWork)
                {
                    if (runOnce) break;
                    await Task.Delay(pollInterval, stoppingToken);
                }
                else
                {
                    logger.LogInformation(
                        "NAV pallet output {OperationId} finished with {Outcome}.",
                        result.OperationId,
                        result.Outcome);
                    if (runOnce) break;
                }
            }
            catch (NavisionPalletOutputQueueUnavailableException exception)
            {
                logger.LogError(exception, "The NAV pallet output queue is unavailable.");
                if (runOnce) break;
                await Task.Delay(pollInterval, stoppingToken);
            }
        }
        while (!stoppingToken.IsCancellationRequested);

        if (runOnce)
            lifetime.StopApplication();
    }
}
