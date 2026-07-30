using System.Data;
using Ebir.Mes.Application.LineSessions;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.LineSessions;

public sealed class SqlCapacitySubstitutionStarter(string? connectionString)
    : ICapacitySubstitutionStarter
{
    public async Task<CapacitySubstitutionRecord> StartAsync(
        StartCapacitySubstitutionCommand request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            throw new LineSessionUnavailableException(
                "La conexión de EBIR_MES_TEST no está configurada.");
        }

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new SqlCommand(
                "prod.iniciar_sustitucion_capacidad",
                connection)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 10
            };
            command.Parameters.Add("@sesion_linea_id", SqlDbType.BigInt).Value =
                request.LineSessionId;
            command.Parameters.Add("@operario_sustituido_id", SqlDbType.BigInt).Value =
                request.ReplacedOperatorId;
            command.Parameters.Add("@supervisor_sustituto_id", SqlDbType.BigInt).Value =
                request.SubstituteSupervisorId;
            command.Parameters.Add(
                "@motivo",
                SqlDbType.NVarChar,
                StartCapacitySubstitution.MaximumReasonLength).Value = request.Reason;
            command.Parameters.Add("@correlacion_id", SqlDbType.UniqueIdentifier).Value =
                request.CorrelationId;

            var substitutionId = command.Parameters.Add(
                "@sustitucion_capacidad_id",
                SqlDbType.BigInt);
            substitutionId.Direction = ParameterDirection.Output;
            var supervisorTimeEntryId = command.Parameters.Add(
                "@fichaje_supervisor_id",
                SqlDbType.BigInt);
            supervisorTimeEntryId.Direction = ParameterDirection.Output;
            var activeResources = command.Parameters.Add(
                "@recursos_activos",
                SqlDbType.Int);
            activeResources.Direction = ParameterDirection.Output;

            await command.ExecuteNonQueryAsync(cancellationToken);
            return new CapacitySubstitutionRecord(
                Convert.ToInt64(substitutionId.Value),
                Convert.ToInt64(supervisorTimeEntryId.Value),
                Convert.ToInt32(activeResources.Value));
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (SqlException exception) when (TryTranslate(exception.Number, out var rejection))
        {
            throw new LineSessionRejectedException(
                rejection.Code,
                rejection.Message,
                exception);
        }
        catch (SqlException exception)
        {
            throw new LineSessionUnavailableException(
                "No se ha podido iniciar la sustitución de capacidad.",
                exception);
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
            52400 => ("CORRELATION_ID_REQUIRED", "La correlación es obligatoria."),
            52401 => ("SUBSTITUTION_REASON_REQUIRED", "El motivo es obligatorio."),
            52402 => ("SUBSTITUTION_EMPLOYEES_MUST_DIFFER",
                "El operario y el supervisor deben ser distintos."),
            52403 => ("REPLACED_EMPLOYEE_NOT_ACTIVE_OPERATOR",
                "El empleado sustituido no es un operario activo."),
            52404 => ("SUBSTITUTE_NOT_ACTIVE_SUPERVISOR",
                "La sustitución requiere un supervisor activo."),
            52405 => ("LINE_SESSION_NOT_FOUND", "La sesión no existe."),
            52406 => ("ORDER_STATE_NOT_ALLOWED_FOR_SUBSTITUTION",
                "La orden no admite iniciar la sustitución."),
            52407 => ("LINE_SESSION_NOT_ACTIVE", "La sesión no está activa."),
            52408 => ("LINE_SESSION_CHANGED", "La sesión cambió durante la operación."),
            52409 => ("LINE_SESSION_STATE_NOT_ALLOWED_FOR_SUBSTITUTION",
                "El estado de la sesión no admite la sustitución."),
            52410 => ("LINE_SESSION_MISMATCH",
                "La línea no corresponde a la sesión activa."),
            52411 => ("LINE_STATE_NOT_ALLOWED_FOR_SUBSTITUTION",
                "El estado de la línea no admite la sustitución."),
            52412 => ("REPLACED_OPERATOR_TIME_ENTRY_NOT_OPEN",
                "El operario no tiene un fichaje abierto en la sesión."),
            52413 => ("SUBSTITUTE_TIME_ENTRY_ALREADY_OPEN",
                "El supervisor ya tiene un fichaje productivo abierto."),
            52414 => ("REPLACED_OPERATOR_STOP_NOT_OPEN",
                "La sustitución requiere un paro abierto del operario."),
            52415 => ("EMPLOYEE_SUBSTITUTION_ALREADY_ACTIVE",
                "El operario o supervisor ya participa en otra sustitución."),
            52416 => ("REPLACED_OPERATOR_ROLE_CHANGED",
                "El empleado sustituido dejó de ser operario activo."),
            52417 => ("SUBSTITUTE_SUPERVISOR_ROLE_CHANGED",
                "El sustituto dejó de ser supervisor activo."),
            52418 => ("SUBSTITUTION_RESOURCE_COUNT_INVALID",
                "La sustitución no restauró exactamente un recurso."),
            _ => default
        };
        return rejection != default;
    }
}
