using Ebir.Mes.Application.Printing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Ebir.Mes.Worker;

public sealed class PrintingWorker(
    ProcessNextPrintJob processor,
    IConfiguration configuration,
    IHostApplicationLifetime lifetime,
    ILogger<PrintingWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var workerId = $"{Environment.MachineName}:{Environment.ProcessId}";
        var pollInterval = TimeSpan.FromMilliseconds(
            Math.Clamp(
                configuration.GetValue("Printing:PollIntervalMilliseconds", 1000),
                100,
                60000));
        var runOnce = configuration.GetValue<bool>("Printing:RunOnce");

        do
        {
            try
            {
                var result = await processor.ExecuteAsync(workerId, stoppingToken);
                if (result.Outcome == ProcessNextPrintJobOutcome.NoWork)
                {
                    if (runOnce) break;
                    await Task.Delay(pollInterval, stoppingToken);
                }
                else
                {
                    logger.LogInformation(
                        "Print job {PrintJobId} finished with {Outcome}.",
                        result.PrintJobId,
                        result.Outcome);
                    if (runOnce) break;
                }
            }
            catch (PrintJobUnavailableException exception)
            {
                logger.LogError(exception, "The persisted printing queue is unavailable.");
                if (runOnce) break;
                await Task.Delay(pollInterval, stoppingToken);
            }
        }
        while (!stoppingToken.IsCancellationRequested);

        if (runOnce)
            lifetime.StopApplication();
    }
}
