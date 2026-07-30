using System.Data;
using Ebir.Mes.Application.Replenishment;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.Replenishment;

public sealed class SqlReplenishmentRequestCreator(string? connectionString)
    : IReplenishmentRequestCreator
{
    public async Task<long> CreateAsync(
        CreateReplenishmentRequestCommand request,
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
                "[log].crear_solicitud_reaprovisionamiento",
                connection)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 10
            };
            command.Parameters.Add("@sesion_linea_id", SqlDbType.BigInt).Value =
                request.LineSessionId;
            command.Parameters.Add("@componente_orden_id", SqlDbType.BigInt).Value =
                request.OrderComponentId;
            command.Parameters.Add("@cantidad_solicitada", SqlDbType.Int).Value =
                request.RequestedQuantity;
            command.Parameters.Add("@solicitada_por_empleado_id", SqlDbType.BigInt).Value =
                request.RequestedByEmployeeId;
            command.Parameters.Add("@scrap_id", SqlDbType.BigInt).Value =
                request.ScrapId is null ? DBNull.Value : request.ScrapId.Value;
            command.Parameters.Add("@correlacion_id", SqlDbType.UniqueIdentifier).Value =
                request.CorrelationId;
            var requestId = command.Parameters.Add("@solicitud_id", SqlDbType.BigInt);
            requestId.Direction = ParameterDirection.Output;
            await command.ExecuteNonQueryAsync(cancellationToken);
            return Convert.ToInt64(requestId.Value);
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
                "No se ha podido crear la solicitud de reaprovisionamiento.",
                exception);
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
            55200 => ("LINE_SESSION_ID_REQUIRED", "La sesión es obligatoria."),
            55201 => ("ORDER_COMPONENT_ID_REQUIRED", "El componente es obligatorio."),
            55202 => ("REQUESTED_QUANTITY_INVALID", "La cantidad debe ser positiva."),
            55203 => ("REQUESTED_BY_EMPLOYEE_ID_REQUIRED",
                "El empleado solicitante es obligatorio."),
            55204 => ("CORRELATION_ID_REQUIRED", "La correlación es obligatoria."),
            55205 => ("REPLENISHMENT_IDEMPOTENCY_LOCK_UNAVAILABLE",
                "No se pudo asegurar la idempotencia de la solicitud."),
            55206 => ("CORRELATION_ID_ALREADY_USED",
                "La correlación ya pertenece a otra operación."),
            55207 => ("CORRELATION_ID_PARAMETER_MISMATCH",
                "La correlación ya se utilizó con parámetros diferentes."),
            55208 => ("LINE_SESSION_NOT_ACTIVE", "La sesión no existe o ya finalizó."),
            55209 => ("LINE_SESSION_STATE_NOT_ALLOWED_FOR_REPLENISHMENT",
                "La sesión no admite solicitudes de reaprovisionamiento."),
            55210 => ("ORDER_STATE_NOT_ALLOWED_FOR_REPLENISHMENT",
                "La orden no admite solicitudes de reaprovisionamiento."),
            55211 => ("REPLENISHMENT_REQUESTER_ROLE_NOT_ALLOWED",
                "La solicitud requiere operario o supervisor activo."),
            55212 => ("ORDER_COMPONENT_NOT_FOUND",
                "El componente no pertenece a la orden de la sesión."),
            55213 => ("LINKED_SCRAP_NOT_FOUND", "El scrap vinculado no existe."),
            55214 => ("LINKED_SCRAP_CONTEXT_MISMATCH",
                "El scrap no pertenece a la misma orden, sesión y línea."),
            55215 => ("LINKED_SCRAP_CANCELLED",
                "No puede solicitarse material para un scrap anulado."),
            55216 => ("LINKED_SCRAP_COMPONENT_MISMATCH",
                "El componente no coincide con el scrap vinculado."),
            55217 => ("LINKED_SCRAP_TRANSACTION_LOCK_UNAVAILABLE",
                "No se pudo bloquear el scrap vinculado."),
            _ => default
        };
        return rejection != default;
    }
}
