using Ebir.Mes.Application.Rfid;

namespace Ebir.Mes.Api.Endpoints.Rfid;

public static class RfidIdentificationEndpoints
{
    public static IEndpointRouteBuilder MapRfidIdentificationEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost("/api/operator-identification/rfid", HandleAsync)
            .WithName("IdentifyEmployeeByRfid")
            .WithSummary("Resuelve localmente una credencial RFID sin conservar su UID.")
            .Produces<RfidEmployeeResponse>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        return endpoints;
    }

    private static async Task<IResult> HandleAsync(
        RfidIdentificationRequest request,
        IdentifyEmployeeByRfid useCase,
        CancellationToken cancellationToken)
    {
        try
        {
            var result = await useCase.ExecuteAsync(request.Credential, cancellationToken);
            if (result.Outcome == IdentifyEmployeeByRfidOutcome.InvalidCredential)
                return Problem(StatusCodes.Status400BadRequest, result.ErrorCode!);
            if (result.Outcome == IdentifyEmployeeByRfidOutcome.NotFound)
                return Problem(StatusCodes.Status404NotFound, result.ErrorCode!);
            var employee = result.Employee!;
            return Results.Ok(new RfidEmployeeResponse(
                employee.EmployeeId,
                employee.NavEmployeeCode,
                employee.FullName));
        }
        catch (RfidIdentificationUnavailableException)
        {
            return Problem(
                StatusCodes.Status503ServiceUnavailable,
                "RFID_IDENTIFICATION_UNAVAILABLE");
        }
    }

    private static IResult Problem(int statusCode, string code) =>
        Results.Problem(
            statusCode: statusCode,
            title: "Identificación RFID no completada",
            extensions: new Dictionary<string, object?> { ["code"] = code });
}
