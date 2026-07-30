using Ebir.Mes.Api.Endpoints.LineIdentification;
using Ebir.Mes.Application.LineIdentification;
using Ebir.Mes.Infrastructure.LineIdentification;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddProblemDetails();
builder.Services.AddScoped<IdentifyLine>();
builder.Services.AddScoped<ILineIdentificationReader>(_ =>
    new SqlLineIdentificationReader(
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
    phase = "line-identification",
    externalIntegrationsEnabled = false
}));

app.MapLineIdentificationEndpoints();

app.Run();

public partial class Program;
