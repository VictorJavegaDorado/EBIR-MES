using Ebir.Mes.Application.Rfid;

namespace Ebir.Mes.Api.Endpoints.Rfid;

public static class SupervisorRfidAuthorizationEndpoints
{
    public static IEndpointRouteBuilder MapSupervisorRfidAuthorizationEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost("/api/supervisor-access/rfid", HandleAsync)
            .WithName("AuthorizeSupervisorAccessByRfid")
            .WithSummary("Autoriza acceso temporal a una funcion supervisada mediante RFID.")
            .Produces<RfidEmployeeResponse>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        return endpoints;
    }

    private static async Task<IResult> HandleAsync(
        RfidIdentificationRequest request,
        AuthorizeSupervisorByRfid useCase,
        CancellationToken cancellationToken)
    {
        try
        {
            var result = await useCase.ExecuteAsync(
                request.Credential,
                cancellationToken);
            if (!result.Authorized)
            {
                var status = result.ErrorCode == "RFID_CREDENTIAL_INVALID"
                    ? StatusCodes.Status400BadRequest
                    : StatusCodes.Status403Forbidden;
                return Problem(status, result.ErrorCode!);
            }

            var supervisor = result.Supervisor!;
            return Results.Ok(new RfidEmployeeResponse(
                supervisor.EmployeeId,
                supervisor.NavEmployeeCode,
                supervisor.FullName));
        }
        catch (RfidIdentificationUnavailableException)
        {
            return Problem(
                StatusCodes.Status503ServiceUnavailable,
                "RFID_SUPERVISOR_AUTHORIZATION_UNAVAILABLE");
        }
    }

    private static IResult Problem(int statusCode, string code) =>
        Results.Problem(
            statusCode: statusCode,
            title: "Autorizacion de supervisor no completada",
            extensions: new Dictionary<string, object?> { ["code"] = code });
}
