using System.Data;
using Ebir.Mes.Application.LineSessions;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.LineSessions;

public sealed class SqlCapacitySubstitutionFinisher(string? connectionString)
    : ICapacitySubstitutionFinisher
{
    public async Task<int> FinishAsync(
        FinishCapacitySubstitutionCommand request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
            throw new LineSessionUnavailableException(
                "La conexión de EBIR_MES_TEST no está configurada.");
        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new SqlCommand(
                "prod.finalizar_sustitucion_capacidad",
                connection)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 10
            };
            command.Parameters.Add("@sustitucion_capacidad_id", SqlDbType.BigInt).Value =
                request.CapacitySubstitutionId;
            command.Parameters.Add("@supervisor_id", SqlDbType.BigInt).Value =
                request.SupervisorId;
            command.Parameters.Add(
                "@motivo",
                SqlDbType.NVarChar,
                FinishCapacitySubstitution.MaximumReasonLength).Value = request.Reason;
            command.Parameters.Add("@correlacion_id", SqlDbType.UniqueIdentifier).Value =
                request.CorrelationId;
            var resources = command.Parameters.Add("@recursos_activos", SqlDbType.Int);
            resources.Direction = ParameterDirection.Output;
            await command.ExecuteNonQueryAsync(cancellationToken);
            return Convert.ToInt32(resources.Value);
        }
        catch (OperationCanceledException) { throw; }
        catch (SqlException exception)
            when (TryTranslate(exception.Number, out var rejection))
        {
            throw new LineSessionRejectedException(
                rejection.Code, rejection.Message, exception);
        }
        catch (SqlException exception)
        {
            throw new LineSessionUnavailableException(
                "No se ha podido finalizar la sustitución.", exception);
        }
        catch (Exception exception)
            when (exception is ArgumentException or InvalidOperationException)
        {
            throw new LineSessionUnavailableException(
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
            52500 => ("CORRELATION_ID_REQUIRED", "La correlación es obligatoria."),
            52501 => ("SUBSTITUTION_FINISH_REASON_REQUIRED", "El motivo es obligatorio."),
            52502 => ("SUPERVISOR_NOT_ACTIVE", "La finalización requiere supervisor activo."),
            52503 => ("CAPACITY_SUBSTITUTION_NOT_FOUND", "La sustitución no existe."),
            52504 => ("SUBSTITUTION_LINE_SESSION_NOT_FOUND", "La sesión no existe."),
            52505 => ("ORDER_STATE_NOT_ALLOWED_FOR_SUBSTITUTION_FINISH",
                "La orden no admite finalizar la sustitución."),
            52506 => ("LINE_SESSION_NOT_ACTIVE", "La sesión no está activa."),
            52507 => ("LINE_SESSION_CHANGED", "La sesión cambió durante la operación."),
            52508 => ("LINE_SESSION_STATE_NOT_ALLOWED_FOR_SUBSTITUTION_FINISH",
                "La sesión no admite finalizar la sustitución."),
            52509 => ("LINE_SESSION_MISMATCH", "La línea no corresponde a la sesión."),
            52510 => ("LINE_STATE_NOT_ALLOWED_FOR_SUBSTITUTION_FINISH",
                "La línea no admite finalizar la sustitución."),
            52511 => ("REPLACED_OPERATOR_TIME_ENTRY_NOT_OPEN",
                "El fichaje del operario sustituido no está abierto."),
            52512 => ("SUBSTITUTE_TIME_ENTRY_NOT_OPEN",
                "El fichaje del supervisor sustituto no está abierto."),
            52513 => ("REPLACED_OPERATOR_STOP_NOT_OPEN",
                "El operario sustituido ya no tiene un paro abierto."),
            52514 => ("CAPACITY_SUBSTITUTION_NOT_ACTIVE",
                "La sustitución no está activa o cambió."),
            52515 => ("AUTHORIZING_SUPERVISOR_ROLE_CHANGED",
                "El autorizador dejó de ser supervisor activo."),
            52516 => ("SUBSTITUTION_HAS_NO_EFFECTIVE_RESOURCE",
                "La sustitución activa no aporta un recurso efectivo."),
            52517 => ("CAPACITY_SUBSTITUTION_FINISH_FAILED",
                "No se pudo finalizar la sustitución activa."),
            52518 => ("SUBSTITUTE_TIME_ENTRY_CLOSE_FAILED",
                "No se pudo cerrar el fichaje del supervisor sustituto."),
            52519 => ("SUBSTITUTION_RESOURCE_COUNT_INVALID",
                "La finalización no retiró exactamente un recurso."),
            _ => default
        };
        return rejection != default;
    }
}
