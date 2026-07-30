using Ebir.Mes.Api.Endpoints.LineIdentification;
using Ebir.Mes.Api.Endpoints.LineSessions;
using Ebir.Mes.Application.LineIdentification;
using Ebir.Mes.Application.LineSessions;
using Ebir.Mes.Infrastructure.LineIdentification;
using Ebir.Mes.Infrastructure.LineSessions;

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
var app = builder.Build();
app.UseExceptionHandler();
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
app.Run();

public partial class Program;
