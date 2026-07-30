using Ebir.Mes.Application.LineSessions;

namespace Ebir.Mes.Api.Endpoints.LineSessions;

public static class LineSessionEndpoints
{
    public static IEndpointRouteBuilder MapLineSessionEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost("/api/line-sessions", HandleOpenAsync)
            .WithName("OpenLineSession")
            .WithSummary("Abre una sesión de línea.")
            .Produces<OpenLineSessionResponse>(StatusCodes.Status201Created)
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        endpoints.MapPost(
                "/api/line-sessions/{sessionId:long}/entries",
                HandleProductiveEntryAsync)
            .WithName("RegisterProductiveEntry")
            .WithSummary("Registra la entrada productiva de un operario.")
            .Produces<RegisterProductiveEntryResponse>(StatusCodes.Status201Created)
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        return endpoints;
    }

    private static async Task<IResult> HandleOpenAsync(
        OpenLineSessionRequest request,
        OpenLineSession openLineSession,
        CancellationToken cancellationToken)
    {
        try
        {
            var command = new OpenLineSessionCommand(
                request.OrderId, request.LineId, request.PalletFormatOrderId,
                request.SupervisorId, request.OutsideScheduleConfirmed,
                request.CorrelationId);
            var result = await openLineSession.ExecuteAsync(command, cancellationToken);

            return result.Outcome switch
            {
                OpenLineSessionOutcome.Opened => Results.Created(
                    $"/api/line-sessions/{result.LineSessionId}",
                    new OpenLineSessionResponse(
                        result.LineSessionId!.Value,
                        request.CorrelationId)),
                OpenLineSessionOutcome.InvalidRequest => ToProblem(
                    StatusCodes.Status400BadRequest,
                    "Solicitud de apertura no válida",
                    result.ErrorCode,
                    result.ErrorMessage),
                OpenLineSessionOutcome.Rejected => ToProblem(
                    StatusCodes.Status409Conflict,
                    "Apertura de sesión rechazada",
                    result.ErrorCode,
                    result.ErrorMessage),
                _ => throw new InvalidOperationException(
                    $"Resultado de apertura no soportado: {result.Outcome}.")
            };
        }
        catch (LineSessionUnavailableException)
        {
            return Unavailable(
                "Apertura de sesión no disponible",
                "No se puede abrir la sesión de línea en este momento.");
        }
    }

    private static async Task<IResult> HandleProductiveEntryAsync(
        long sessionId,
        RegisterProductiveEntryRequest request,
        RegisterProductiveEntry registerProductiveEntry,
        CancellationToken cancellationToken)
    {
        try
        {
            var command = new RegisterProductiveEntryCommand(
                sessionId,
                request.EmployeeId,
                request.CorrelationId);
            var result = await registerProductiveEntry.ExecuteAsync(
                command,
                cancellationToken);

            return result.Outcome switch
            {
                ProductiveEntryOutcome.Registered => Results.Created(
                    $"/api/line-sessions/{sessionId}/entries/{result.Entry!.TimeEntryId}",
                    new RegisterProductiveEntryResponse(
                        result.Entry.TimeEntryId,
                        result.Entry.PalletReservationId,
                        request.CorrelationId)),
                ProductiveEntryOutcome.InvalidRequest => ToProblem(
                    StatusCodes.Status400BadRequest,
                    "Solicitud de entrada productiva no válida",
                    result.ErrorCode,
                    result.ErrorMessage),
                ProductiveEntryOutcome.Rejected => ToProblem(
                    StatusCodes.Status409Conflict,
                    "Entrada productiva rechazada",
                    result.ErrorCode,
                    result.ErrorMessage),
                _ => throw new InvalidOperationException(
                    $"Resultado de entrada no soportado: {result.Outcome}.")
            };
        }
        catch (LineSessionUnavailableException)
        {
            return Unavailable(
                "Entrada productiva no disponible",
                "No se puede registrar la entrada productiva en este momento.");
        }
    }

    private static IResult ToProblem(
        int statusCode,
        string title,
        string? errorCode,
        string? errorMessage)
    {
        return Results.Problem(
            statusCode: statusCode,
            title: title,
            detail: errorMessage,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = errorCode
            });
    }

    private static IResult Unavailable(string title, string detail)
    {
        return Results.Problem(
            statusCode: StatusCodes.Status503ServiceUnavailable,
            title: title,
            detail: detail,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "LINE_SESSION_UNAVAILABLE"
            });
    }
}
