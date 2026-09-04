using Ebir.Mes.Application.PalletRecovery;

namespace Ebir.Mes.Api.Endpoints.PalletRecovery;

public static class PalletRecoveryEndpoints
{
    public static IEndpointRouteBuilder MapPalletRecoveryEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet("/api/line-sessions/{lineSessionId:long}/latest-pallet-recovery", GetAsync)
            .WithName("GetLatestPalletRecovery").Produces<PalletRecoveryStateRecord>()
            .Produces(StatusCodes.Status204NoContent).ProducesProblem(503);
        endpoints.MapPost("/api/nav/pallet-outputs/{navOperationId:long}/retry-reconciliation", RetryAsync)
            .WithName("RetryPalletNavReconciliation")
            .Produces<RetriedPalletNavReconciliationRecord>()
            .ProducesProblem(400).ProducesProblem(409).ProducesProblem(503);
        return endpoints;
    }

    private static async Task<IResult> GetAsync(
        long lineSessionId,
        GetLatestPalletRecovery useCase,
        CancellationToken cancellationToken)
    {
        if (lineSessionId <= 0) return Problem(400, "PALLET_RECOVERY_KEY_INVALID", "La sesion no es valida.");
        try
        {
            var state = await useCase.ExecuteAsync(lineSessionId, cancellationToken);
            return state is null ? Results.NoContent() : Results.Ok(state);
        }
        catch (PalletRecoveryUnavailableException)
        {
            return Problem(503, "PALLET_RECOVERY_UNAVAILABLE", "No se puede consultar el ultimo pale.");
        }
    }

    private static async Task<IResult> RetryAsync(
        long navOperationId,
        RetryPalletNavReconciliationRequest request,
        RetryPalletNavReconciliation useCase,
        CancellationToken cancellationToken)
    {
        try
        {
            var result = await useCase.ExecuteAsync(new(
                navOperationId, request.RequestedBySupervisorId,
                request.Reason, request.CorrelationId), cancellationToken);
            return Results.Accepted(
                $"/api/nav/pallet-outputs/{navOperationId}", result);
        }
        catch (PalletRecoveryRejectedException exception)
        {
            return Problem(
                exception.Code.EndsWith("INVALID", StringComparison.Ordinal) ? 400 : 409,
                exception.Code, exception.Message);
        }
        catch (PalletRecoveryUnavailableException)
        {
            return Problem(503, "NAV_RECONCILIATION_RETRY_UNAVAILABLE",
                "No se puede solicitar la conciliacion NAV en este momento.");
        }
    }

    private static IResult Problem(int status, string code, string detail) =>
        Results.Problem(statusCode: status, detail: detail,
            extensions: new Dictionary<string, object?> { ["code"] = code });
}

public sealed record RetryPalletNavReconciliationRequest(
    long RequestedBySupervisorId,
    string Reason,
    Guid CorrelationId);
