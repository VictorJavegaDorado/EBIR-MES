using System.Data;
using Ebir.Mes.Application.LineSessions;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.LineSessions;

public sealed class SqlOperatorStopFinisher(string? connectionString)
    : IOperatorStopFinisher
{
    public async Task<FinishedOperatorStopRecord> FinishAsync(
        FinishOperatorStopCommand request, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
            throw new LineSessionUnavailableException("EBIR_MES_TEST no configurada.");
        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new SqlCommand(
                "prod.finalizar_paro_operario", connection)
            { CommandType = CommandType.StoredProcedure, CommandTimeout = 10 };
            command.Parameters.Add("@sesion_linea_id", SqlDbType.BigInt).Value =
                request.LineSessionId;
            command.Parameters.Add("@empleado_id", SqlDbType.BigInt).Value =
                request.EmployeeId;
            command.Parameters.Add("@correlacion_id", SqlDbType.UniqueIdentifier).Value =
                request.CorrelationId;
            var stop = command.Parameters.Add("@paro_operario_id", SqlDbType.BigInt);
            stop.Direction = ParameterDirection.Output;
            var substitution = command.Parameters.Add(
                "@sustitucion_finalizada_id", SqlDbType.BigInt);
            substitution.Direction = ParameterDirection.Output;
            var resources = command.Parameters.Add("@recursos_activos", SqlDbType.Int);
            resources.Direction = ParameterDirection.Output;
            await command.ExecuteNonQueryAsync(cancellationToken);
            return new(
                Convert.ToInt64(stop.Value),
                substitution.Value is DBNull ? null : Convert.ToInt64(substitution.Value),
                Convert.ToInt32(resources.Value));
        }
        catch (OperationCanceledException) { throw; }
        catch (SqlException ex) when (TryTranslate(ex.Number, out var rejection))
        { throw new LineSessionRejectedException(rejection.Code, rejection.Message, ex); }
        catch (SqlException ex)
        { throw new LineSessionUnavailableException("No se pudo finalizar el paro.", ex); }
        catch (Exception ex) when (ex is ArgumentException or InvalidOperationException)
        { throw new LineSessionUnavailableException("Configuración no válida.", ex); }
    }

    internal static bool TryTranslate(int number, out (string Code, string Message) rejection)
    {
        rejection = number switch
        {
            52300 => ("CORRELATION_ID_REQUIRED", "La correlación es obligatoria."),
            52301 => ("EMPLOYEE_NOT_ACTIVE_OPERATOR", "El retorno requiere operario activo."),
            52302 => ("LINE_SESSION_NOT_FOUND", "La sesión no existe."),
            52303 => ("ORDER_STATE_NOT_ALLOWED_FOR_RETURN", "La orden no admite el retorno."),
            52304 => ("LINE_SESSION_NOT_ACTIVE", "La sesión no está activa."),
            52305 => ("LINE_SESSION_CHANGED", "La sesión cambió durante la operación."),
            52306 => ("LINE_SESSION_STATE_NOT_ALLOWED_FOR_RETURN", "La sesión no admite el retorno."),
            52307 => ("LINE_SESSION_MISMATCH", "La línea no corresponde a la sesión."),
            52308 => ("LINE_STATE_NOT_ALLOWED_FOR_RETURN", "La línea no admite el retorno."),
            52309 => ("EMPLOYEE_TIME_ENTRY_NOT_OPEN", "El operario no tiene fichaje abierto."),
            52310 => ("OPERATOR_STOP_NOT_OPEN", "El operario no tiene un paro abierto."),
            52311 => ("SUBSTITUTION_STOP_MISMATCH", "La sustitución no corresponde al paro."),
            52312 => ("SUBSTITUTE_TIME_ENTRY_NOT_OPEN", "El sustituto no tiene fichaje abierto."),
            52313 => ("EMPLOYEE_ROLE_CHANGED", "El empleado dejó de ser operario activo."),
            52314 => ("OPERATOR_STOP_CHANGED", "El paro cambió durante la operación."),
            52315 => ("SUBSTITUTION_CHANGED", "La sustitución cambió durante la operación."),
            52316 => ("SUBSTITUTE_TIME_ENTRY_CLOSE_FAILED", "No se pudo cerrar el fichaje sustituto."),
            52317 => ("NO_EFFECTIVE_RESOURCES_AFTER_RETURN", "El retorno no produjo recursos efectivos."),
            _ => default
        };
        return rejection != default;
    }
}
