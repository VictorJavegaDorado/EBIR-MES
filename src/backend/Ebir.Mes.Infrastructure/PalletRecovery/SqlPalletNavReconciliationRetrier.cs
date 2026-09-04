using System.Data;
using Ebir.Mes.Application.PalletRecovery;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.PalletRecovery;

public sealed class SqlPalletNavReconciliationRetrier(string? connectionString)
    : IPalletNavReconciliationRetrier
{
    public async Task<RetriedPalletNavReconciliationRecord> RetryAsync(
        RetryPalletNavReconciliationCommand request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
            throw new PalletRecoveryUnavailableException(
                "La conexion de EBIR_MES_TEST no esta configurada.");
        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new SqlCommand(
                "nav.solicitar_reconciliacion_salida_palet", connection)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 10
            };
            command.Parameters.Add("@operacion_nav_id", SqlDbType.BigInt).Value =
                request.NavOperationId;
            command.Parameters.Add("@solicitado_por_supervisor_id", SqlDbType.BigInt).Value =
                request.RequestedBySupervisorId;
            command.Parameters.Add("@motivo", SqlDbType.NVarChar, 500).Value = request.Reason;
            command.Parameters.Add("@correlacion_id", SqlDbType.UniqueIdentifier).Value =
                request.CorrelationId;
            var nextAttempt = command.Parameters.Add("@proximo_numero_intento", SqlDbType.Int);
            nextAttempt.Direction = ParameterDirection.Output;
            await command.ExecuteNonQueryAsync(cancellationToken);
            return new(request.NavOperationId, Convert.ToInt32(nextAttempt.Value));
        }
        catch (OperationCanceledException) { throw; }
        catch (SqlException exception) when (TryTranslate(exception.Number, out var rejection))
        {
            throw new PalletRecoveryRejectedException(
                rejection.Code, rejection.Message, exception);
        }
        catch (SqlException exception)
        {
            throw new PalletRecoveryUnavailableException(
                "No se ha podido solicitar la conciliacion NAV.", exception);
        }
    }

    internal static bool TryTranslate(
        int number,
        out (string Code, string Message) rejection)
    {
        rejection = number switch
        {
            56600 => ("NAV_OPERATION_ID_INVALID", "La operacion NAV no es valida."),
            56601 => ("NAV_RETRY_SUPERVISOR_REQUIRED", "La conciliacion requiere un supervisor."),
            56602 => ("NAV_RETRY_REASON_INVALID", "El motivo no es valido."),
            56603 => ("CORRELATION_ID_REQUIRED", "La correlacion es obligatoria."),
            56604 => ("NAV_RETRY_LOCK_UNAVAILABLE", "No se pudo asegurar la operacion."),
            56605 => ("CORRELATION_ID_ALREADY_USED", "La correlacion ya pertenece a otra operacion."),
            56606 => ("CORRELATION_ID_PARAMETER_MISMATCH", "La correlacion ya se uso con otros datos."),
            56607 => ("NAV_RETRY_SUPERVISOR_NOT_ACTIVE", "Se requiere un supervisor activo."),
            56608 => ("NAV_RECONCILIATION_NOT_RETRYABLE", "La salida no admite conciliacion manual."),
            56609 => ("NAV_RECONCILIATION_ALREADY_RUNNING", "La conciliacion ya esta en curso."),
            _ => default
        };
        return rejection != default;
    }
}
