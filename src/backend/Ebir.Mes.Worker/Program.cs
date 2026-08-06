using Ebir.Mes.Application.Printing;
using Ebir.Mes.Application.NavisionOutput;
using Ebir.Mes.Infrastructure.NavisionOutput;
using Ebir.Mes.Infrastructure.Printing;
using Ebir.Mes.Integrations.NavisionOutput;
using Ebir.Mes.Integrations.Printing;
using Ebir.Mes.Worker;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var builder = Host.CreateApplicationBuilder(args);

var navisionOutputEnabled =
    builder.Configuration.GetValue<bool>("NavisionOutput:Enabled");
if (navisionOutputEnabled)
{
    var endpointValue = builder.Configuration["NavisionOutput:ServiceEndpoint"];
    if (!Uri.TryCreate(endpointValue, UriKind.Absolute, out var endpoint))
        throw new InvalidOperationException(
            "NavisionOutput:ServiceEndpoint is required when NAV output is enabled.");

    var requestTimeout = TimeSpan.FromSeconds(
        Math.Clamp(
            builder.Configuration.GetValue("NavisionOutput:RequestTimeoutSeconds", 10),
            1,
            30));
    var assemblyLineMappings = builder.Configuration
        .GetSection("NavisionOutput:AssemblyLineMappings")
        .GetChildren()
        .Where(child => !string.IsNullOrWhiteSpace(child.Value))
        .ToDictionary(
            child => child.Key,
            child => child.Value!,
            StringComparer.OrdinalIgnoreCase);
    var options = new NavisionPalletOutputOptions(
        endpoint,
        requestTimeout,
        assemblyLineMappings);
    const string clientName = "NavisionPalletOutput";
    builder.Services.AddHttpClient(clientName)
        .ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler
        {
            UseDefaultCredentials = true,
            PreAuthenticate = true,
            AllowAutoRedirect = false
        });
    builder.Services.AddSingleton<INavisionPalletOutputQueue>(_ =>
        new SqlNavisionPalletOutputQueue(
            builder.Configuration.GetConnectionString("MesDatabase")));
    builder.Services.AddSingleton<INavisionPalletOutputSender>(services =>
        new NavisionSoapPalletOutputSender(
            services.GetRequiredService<IHttpClientFactory>().CreateClient(clientName),
            options));
    builder.Services.AddSingleton<ProcessNextNavisionPalletOutput>();
    builder.Services.AddHostedService<NavisionPalletOutputWorker>();
}

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
