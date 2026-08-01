using Ebir.Mes.Application.Printing;
using Ebir.Mes.Infrastructure.Printing;
using Ebir.Mes.Integrations.Printing;
using Ebir.Mes.Worker;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var builder = Host.CreateApplicationBuilder(args);

var printingEnabled = builder.Configuration.GetValue<bool>("Printing:Enabled");
if (printingEnabled)
{
    var mode = builder.Configuration["Printing:Mode"];
    if (!string.Equals(mode, "Simulated", StringComparison.OrdinalIgnoreCase))
        throw new InvalidOperationException(
            "Only the explicitly selected Simulated printing mode is available.");

    var outputDirectory = builder.Configuration["Printing:SimulatedOutputDirectory"];
    if (string.IsNullOrWhiteSpace(outputDirectory))
        throw new InvalidOperationException(
            "Printing:SimulatedOutputDirectory is required.");

    builder.Services.AddSingleton<IPrintJobQueue>(_ =>
        new SqlPrintJobQueue(
            builder.Configuration.GetConnectionString("MesDatabase")));
    builder.Services.AddSingleton<IPrinter>(
        new SimulatedPrinter(new(outputDirectory)));
    builder.Services.AddSingleton<ProcessNextPrintJob>();
    builder.Services.AddHostedService<PrintingWorker>();
}

var host = builder.Build();

await host.RunAsync();
