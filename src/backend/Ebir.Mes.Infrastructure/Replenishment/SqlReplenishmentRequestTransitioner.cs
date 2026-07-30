using System.Data;
using Ebir.Mes.Application.Replenishment;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.Replenishment;

public sealed class SqlReplenishmentRequestTransitioner(string? connectionString)
    : IReplenishmentRequestTransitioner
{
    public async Task TransitionAsync(
        TransitionReplenishmentRequestCommand request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
            throw new ReplenishmentUnavailableException(
                "La conexión de EBIR_MES_TEST no está configurada.");
        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new SqlCommand(
                "[log].transicionar_solicitud_reaprovisionamiento",
                connection)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 10
            };
            command.Parameters.Add("@solicitud_id", SqlDbType.BigInt).Value =
                request.RequestId;
            command.Parameters.Add("@estado_nuevo", SqlDbType.NVarChar, 20).Value =
                request.NewState;
            command.Parameters.Add("@empleado_id", SqlDbType.BigInt).Value =
                request.EmployeeId;
            command.Parameters.Add(
                "@comentario",
                SqlDbType.NVarChar,
                TransitionReplenishmentRequest.MaximumCommentLength).Value =
                request.Comment is null ? DBNull.Value : request.Comment;
            command.Parameters.Add("@correlacion_id", SqlDbType.UniqueIdentifier).Value =
                request.CorrelationId;
            await command.ExecuteNonQueryAsync(cancellationToken);
        }
        catch (OperationCanceledException) { throw; }
        catch (SqlException exception)
            when (TryTranslate(exception.Number, out var rejection))
        {
            throw new ReplenishmentRejectedException(
                rejection.Code, rejection.Message, exception);
        }
        catch (SqlException exception)
        {
            throw new ReplenishmentUnavailableException(
                "No se ha podido transicionar la solicitud.", exception);
        }
        catch (Exception exception)
            when (exception is ArgumentException or InvalidOperationException)
        {
            throw new ReplenishmentUnavailableException(
                "La conexión de EBIR_MES_TEST no tiene una configuración válida.",
                exception);
        }
    }

    internal static bool TryTranslate(
        int number,
        out (string Code, string Message) rejection)
    {
        rejection = number switch
        {
            55300 => ("REPLENISHMENT_REQUEST_ID_REQUIRED",
                "La solicitud es obligatoria."),
            55301 => ("REPLENISHMENT_TARGET_STATE_INVALID",
                "El estado destino no es válido."),
            55302 => ("REPLENISHMENT_EMPLOYEE_ID_REQUIRED",
                "El aprovisionador es obligatorio."),
            55303 => ("REPLENISHMENT_TRANSITION_COMMENT_REQUIRED",
                "El rechazo o la cancelación requieren motivo."),
            55304 => ("CORRELATION_ID_REQUIRED", "La correlación es obligatoria."),
            55305 => ("REPLENISHMENT_TRANSITION_IDEMPOTENCY_LOCK_UNAVAILABLE",
                "No se pudo asegurar la idempotencia de la transición."),
            55306 => ("CORRELATION_ID_PARAMETER_MISMATCH",
                "La correlación ya se utilizó con parámetros diferentes."),
            55307 => ("REPLENISHMENT_REQUEST_NOT_FOUND", "La solicitud no existe."),
            55308 => ("REPLENISHMENT_EMPLOYEE_NOT_ACTIVE",
                "La transición requiere aprovisionador activo."),
            55309 => ("REPLENISHMENT_REQUEST_ALREADY_TERMINAL",
                "La solicitud ya está en un estado terminal."),
            55310 => ("REPLENISHMENT_REQUEST_ASSIGNEE_MISMATCH",
                "La solicitud debe continuarla el aprovisionador asignado."),
            55311 => ("REPLENISHMENT_TRANSITION_NOT_ALLOWED",
                "La transición de estado no está permitida."),
            _ => default
        };
        return rejection != default;
    }
}
