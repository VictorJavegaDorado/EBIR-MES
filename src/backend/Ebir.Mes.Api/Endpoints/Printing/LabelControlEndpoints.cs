using Ebir.Mes.Application.Printing.LabelControl;

namespace Ebir.Mes.Api.Endpoints.Printing;

public static class LabelControlEndpoints
{
    public static IEndpointRouteBuilder MapLabelControlEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet("/api/label-control", HandleAsync)
            .WithName("GetLabelControl")
            .WithSummary("Lista ordenes y palets disponibles para control de etiquetas.")
            .Produces<LabelControlSnapshotRecord>()
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        return endpoints;
    }

    private static async Task<IResult> HandleAsync(
        GetLabelControl useCase,
        CancellationToken cancellationToken)
    {
        try
        {
            return Results.Ok(await useCase.ExecuteAsync(cancellationToken));
        }
        catch (LabelControlUnavailableException)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status503ServiceUnavailable,
                title: "Control de etiquetas no disponible",
                detail: "No se pueden consultar las ordenes y palets en este momento.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "LABEL_CONTROL_UNAVAILABLE"
                });
        }
    }
}
