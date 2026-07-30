using Ebir.Mes.Application.Pallets.ClosePalletOptions;

namespace Ebir.Mes.Api.Endpoints.Pallets;

public static class PalletCloseOptionsEndpoints
{
    public static IEndpointRouteBuilder MapPalletCloseOptionsEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet("/api/lines/{lineId:long}/pallet-close-options", HandleAsync)
            .WithName("GetPalletCloseOptions")
            .WithSummary("Obtiene las reservas y empleados disponibles para cerrar un palé.")
            .Produces<PalletCloseOptionsResponse>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        return endpoints;
    }

    private static async Task<IResult> HandleAsync(
        long lineId,
        GetPalletCloseOptions useCase,
        CancellationToken cancellationToken)
    {
        if (lineId <= 0)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status400BadRequest,
                title: "Línea no válida",
                detail: "La línea debe ser un identificador positivo.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "LINE_ID_INVALID"
                });
        }

        try
        {
            var result = await useCase.ExecuteAsync(lineId, cancellationToken);
            return Results.Ok(new PalletCloseOptionsResponse(
                result.Reservations,
                result.Employees,
                result.Supervisors));
        }
        catch (PalletCloseOptionsUnavailableException)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status503ServiceUnavailable,
                title: "Opciones de cierre no disponibles",
                detail: "No se pueden consultar las opciones de cierre en este momento.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "PALLET_CLOSE_OPTIONS_UNAVAILABLE"
                });
        }
    }
}

public sealed record PalletCloseOptionsResponse(
    IReadOnlyList<PalletReservationOption> Reservations,
    IReadOnlyList<PalletEmployeeOption> Employees,
    IReadOnlyList<PalletEmployeeOption> Supervisors);
