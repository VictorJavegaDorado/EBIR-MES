using Ebir.Mes.Api.Endpoints.LineIdentification;
using Ebir.Mes.Api.Endpoints.LineSessions;
using Ebir.Mes.Api.Endpoints.Pallets;
using Ebir.Mes.Api.Endpoints.ProductionOrders;
using Ebir.Mes.Api.Endpoints.Replenishment;
using Ebir.Mes.Api.Endpoints.Scrap;
using Ebir.Mes.Application.LineIdentification;
using Ebir.Mes.Application.LineSessions;
using Ebir.Mes.Application.Pallets.ClosePallet;
using Ebir.Mes.Application.Pallets.ClosePalletOptions;
using Ebir.Mes.Application.ProductionOrders;
using Ebir.Mes.Application.Replenishment;
using Ebir.Mes.Application.Scrap;
using Ebir.Mes.Infrastructure.LineIdentification;
using Ebir.Mes.Infrastructure.LineSessions;
using Ebir.Mes.Infrastructure.Pallets;
using Ebir.Mes.Infrastructure.ProductionOrders;
using Ebir.Mes.Infrastructure.Replenishment;
using Ebir.Mes.Infrastructure.Scrap;
using Ebir.Mes.Integrations.Navision;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddProblemDetails();
builder.Services.AddScoped<IdentifyLine>();
builder.Services.AddScoped<OpenLineSession>();
builder.Services.AddScoped<RegisterProductiveEntry>();
builder.Services.AddScoped<RegisterProductiveExit>();
builder.Services.AddScoped<MarkShiftChangePending>();
builder.Services.AddScoped<FinishLineSession>();
builder.Services.AddScoped<StartOperatorStop>();
builder.Services.AddScoped<FinishOperatorStop>();
builder.Services.AddScoped<StartCapacitySubstitution>();
builder.Services.AddScoped<FinishCapacitySubstitution>();
builder.Services.AddScoped<CorrectCurrentShiftTimeEntry>();
builder.Services.AddScoped<RegisterScrap>();
builder.Services.AddScoped<ReviewScrap>();
builder.Services.AddScoped<CreateReplenishmentRequest>();
builder.Services.AddScoped<TransitionReplenishmentRequest>();
builder.Services.AddScoped<ClosePallet>();
builder.Services.AddScoped<GetPalletCloseOptions>();
builder.Services.AddScoped<SynchronizeProductionOrder>();
builder.Services.AddHttpClient(
        ProductionOrderSynchronizationConfiguration.HttpClientName)
    .ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler
    {
        UseDefaultCredentials = true,
        PreAuthenticate = true
    });
builder.Services.AddScoped<IProductionOrderSource>(services =>
{
    var configuration = ProductionOrderSynchronizationConfiguration.Read(
        services.GetRequiredService<IConfiguration>());
    return new NavisionProductionOrderSource(
        services.GetRequiredService<IHttpClientFactory>().CreateClient(
            ProductionOrderSynchronizationConfiguration.HttpClientName),
        configuration.CreateNavisionOptions());
});
builder.Services.AddScoped<IProductionOrderSnapshotStore>(services =>
    new SqlProductionOrderSnapshotStore(
        services.GetRequiredService<IConfiguration>()
            .GetConnectionString("MesDatabase")));
builder.Services.AddScoped<ILineIdentificationReader>(_ =>
    new SqlLineIdentificationReader(
        builder.Configuration.GetConnectionString("MesDatabase")));
builder.Services.AddScoped<ILineSessionOpener>(_ =>
    new SqlLineSessionOpener(
        builder.Configuration.GetConnectionString("MesDatabase")));
builder.Services.AddScoped<IProductiveEntryRegistrar>(_ =>
    new SqlProductiveEntryRegistrar(
        builder.Configuration.GetConnectionString("MesDatabase")));
builder.Services.AddScoped<IProductiveExitRegistrar>(_ =>
    new SqlProductiveExitRegistrar(
        builder.Configuration.GetConnectionString("MesDatabase")));
builder.Services.AddScoped<IShiftChangePendingMarker>(_ =>
    new SqlShiftChangePendingMarker(
        builder.Configuration.GetConnectionString("MesDatabase")));
builder.Services.AddScoped<ILineSessionFinisher>(_ =>
    new SqlLineSessionFinisher(
        builder.Configuration.GetConnectionString("MesDatabase")));
builder.Services.AddScoped<IOperatorStopStarter>(_ =>
    new SqlOperatorStopStarter(
        builder.Configuration.GetConnectionString("MesDatabase")));
builder.Services.AddScoped<IOperatorStopFinisher>(_ =>
    new SqlOperatorStopFinisher(
        builder.Configuration.GetConnectionString("MesDatabase")));
builder.Services.AddScoped<ICapacitySubstitutionStarter>(_ =>
    new SqlCapacitySubstitutionStarter(
        builder.Configuration.GetConnectionString("MesDatabase")));
builder.Services.AddScoped<ICapacitySubstitutionFinisher>(_ =>
    new SqlCapacitySubstitutionFinisher(
        builder.Configuration.GetConnectionString("MesDatabase")));
builder.Services.AddScoped<ICurrentShiftTimeEntryCorrector>(_ =>
    new SqlCurrentShiftTimeEntryCorrector(
        builder.Configuration.GetConnectionString("MesDatabase")));
builder.Services.AddScoped<IScrapRegistrar>(_ =>
    new SqlScrapRegistrar(
        builder.Configuration.GetConnectionString("MesDatabase")));
builder.Services.AddScoped<IScrapReviewer>(_ =>
    new SqlScrapReviewer(
        builder.Configuration.GetConnectionString("MesDatabase")));
builder.Services.AddScoped<IReplenishmentRequestCreator>(_ =>
    new SqlReplenishmentRequestCreator(
        builder.Configuration.GetConnectionString("MesDatabase")));
builder.Services.AddScoped<IReplenishmentRequestTransitioner>(_ =>
    new SqlReplenishmentRequestTransitioner(
        builder.Configuration.GetConnectionString("MesDatabase")));
builder.Services.AddScoped<IPalletCloser>(_ =>
    new SqlPalletCloser(
        builder.Configuration.GetConnectionString("MesDatabase")));
builder.Services.AddScoped<IPalletCloseOptionsReader>(_ =>
    new SqlPalletCloseOptionsReader(
        builder.Configuration.GetConnectionString("MesDatabase")));
var app = builder.Build();
app.UseExceptionHandler();
app.UseDefaultFiles();
app.UseStaticFiles();
app.MapGet("/health/live", () => Results.Ok(new
{
    status = "ok",
    service = "Ebir.Mes.Api"
}));
app.MapGet("/api/system/info", () => Results.Ok(new
{
    name = "EBIR MES",
    phase = "line-sessions",
    externalIntegrationsEnabled = false
}));
app.MapLineIdentificationEndpoints();
app.MapLineSessionEndpoints();
app.MapProductiveExitEndpoints();
app.MapShiftChangePendingEndpoints();
app.MapFinishLineSessionEndpoints();
app.MapOperatorStopEndpoints();
app.MapFinishOperatorStopEndpoints();
app.MapCapacitySubstitutionEndpoints();
app.MapFinishCapacitySubstitutionEndpoints();
app.MapCorrectCurrentShiftTimeEntryEndpoints();
app.MapRegisterScrapEndpoints();
app.MapReviewScrapEndpoints();
app.MapCreateReplenishmentRequestEndpoints();
app.MapTransitionReplenishmentRequestEndpoints();
app.MapClosePalletEndpoints();
app.MapPalletCloseOptionsEndpoints();
app.MapProductionOrderSynchronizationEndpoints();
app.MapFallback("{*path:nonfile}", async context =>
{
    if (context.Request.Path.StartsWithSegments(
        "/api",
        StringComparison.OrdinalIgnoreCase))
    {
        context.Response.StatusCode = StatusCodes.Status404NotFound;
        return;
    }

    var environment =
        context.RequestServices.GetRequiredService<IWebHostEnvironment>();
    var indexPath = Path.Combine(
        environment.WebRootPath ?? string.Empty,
        "index.html");

    if (!File.Exists(indexPath))
    {
        context.Response.StatusCode = StatusCodes.Status404NotFound;
        return;
    }

    await Results.File(
        indexPath,
        "text/html; charset=utf-8").ExecuteAsync(context);
});
app.Run();

public partial class Program;
