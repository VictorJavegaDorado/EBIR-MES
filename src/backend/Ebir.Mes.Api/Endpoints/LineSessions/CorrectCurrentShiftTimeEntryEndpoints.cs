using Ebir.Mes.Application.LineSessions;

namespace Ebir.Mes.Api.Endpoints.LineSessions;

public static class CorrectCurrentShiftTimeEntryEndpoints
{
    public static IEndpointRouteBuilder MapCorrectCurrentShiftTimeEntryEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost(
                "/api/time-entries/{timeEntryId:long}/corrections",
                HandleAsync)
            .WithName("CorrectCurrentShiftTimeEntry")
            .WithSummary("Corrige un fichaje del turno actual.")
            .Produces<CorrectCurrentShiftTimeEntryResponse>()
            .ProducesProblem(400).ProducesProblem(409).ProducesProblem(503);
        return endpoints;
    }

    private static async Task<IResult> HandleAsync(
        long timeEntryId,
        CorrectCurrentShiftTimeEntryRequest request,
        CorrectCurrentShiftTimeEntry useCase,
        CancellationToken cancellationToken)
    {
        try
        {
            var result = await useCase.ExecuteAsync(
                new(
                    timeEntryId,
                    request.CorrectedEntryUtc,
                    request.CorrectedExitUtc,
                    request.SupervisorId,
                    request.Reason,
                    request.CorrelationId),
                cancellationToken);
            return result.Outcome switch
            {
                CorrectCurrentShiftTimeEntryOutcome.Corrected => Results.Ok(
                    new CorrectCurrentShiftTimeEntryResponse(
                        timeEntryId,
                        request.CorrelationId)),
                CorrectCurrentShiftTimeEntryOutcome.InvalidRequest => Problem(
                    400, "Solicitud de corrección no válida", result),
                CorrectCurrentShiftTimeEntryOutcome.Rejected => Problem(
                    409, "Corrección de fichaje rechazada", result),
                _ => throw new InvalidOperationException()
            };
        }
        catch (LineSessionUnavailableException)
        {
            return Results.Problem(
                statusCode: 503,
                title: "Corrección no disponible",
                detail: "No se puede corregir el fichaje en este momento.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "LINE_SESSION_UNAVAILABLE"
                });
        }
    }

    private static IResult Problem(
        int status,
        string title,
        CorrectCurrentShiftTimeEntryResult result) =>
        Results.Problem(
            statusCode: status,
            title: title,
            detail: result.ErrorMessage,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = result.ErrorCode
            });
}
