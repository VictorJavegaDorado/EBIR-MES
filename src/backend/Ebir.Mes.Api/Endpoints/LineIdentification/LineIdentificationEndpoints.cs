using Ebir.Mes.Application.LineIdentification;

namespace Ebir.Mes.Api.Endpoints.LineIdentification;

public static class LineIdentificationEndpoints
{
    public static IEndpointRouteBuilder MapLineIdentificationEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet("/api/lines/{code}", HandleAsync)
            .WithName("IdentifyLine")
            .WithSummary("Identifica una línea activa por su código.")
            .Produces<LineIdentificationResponse>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        return endpoints;
    }

    private static async Task<IResult> HandleAsync(
        string code,
        IdentifyLine identifyLine,
        CancellationToken cancellationToken)
    {
        try
        {
            var result = await identifyLine.ExecuteAsync(code, cancellationToken);

            return result.Outcome switch
            {
                LineIdentificationOutcome.Found => Results.Ok(ToResponse(result.Line!)),
                LineIdentificationOutcome.InvalidCode => ToProblem(
                    StatusCodes.Status400BadRequest,
                    "Código de línea no válido",
                    result),
                LineIdentificationOutcome.NotFound => ToProblem(
                    StatusCodes.Status404NotFound,
                    "Línea no encontrada",
                    result),
                LineIdentificationOutcome.Inactive => ToProblem(
                    StatusCodes.Status409Conflict,
                    "Línea desactivada",
                    result),
                LineIdentificationOutcome.Ambiguous => ToProblem(
                    StatusCodes.Status409Conflict,
                    "Código de línea ambiguo",
                    result),
                _ => throw new InvalidOperationException(
                    $"Resultado de identificación no soportado: {result.Outcome}.")
            };
        }
        catch (LineIdentificationUnavailableException)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status503ServiceUnavailable,
                title: "Consulta de líneas no disponible",
                detail: "No se puede consultar el estado de las líneas en este momento.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "LINE_IDENTIFICATION_UNAVAILABLE"
                });
        }
    }

    private static LineIdentificationResponse ToResponse(LineIdentificationRecord line)
    {
        return new LineIdentificationResponse(
            line.LineId,
            line.Code,
            line.Name,
            line.WorkCenterCode,
            line.WorkCenterName,
            line.OperationalStatus);
    }

    private static IResult ToProblem(
        int statusCode,
        string title,
        LineIdentificationResult result)
    {
        return Results.Problem(
            statusCode: statusCode,
            title: title,
            detail: result.ErrorMessage,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = result.ErrorCode,
                ["lineCode"] = result.NormalizedCode
            });
    }
}

