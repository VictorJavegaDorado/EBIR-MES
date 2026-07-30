using System.Data;
using Ebir.Mes.Application.LineSessions;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.LineSessions;

public sealed class SqlOperatorStopStarter(string? connectionString) : IOperatorStopStarter
{
    public async Task<OperatorStopRecord> StartAsync(
        StartOperatorStopCommand request, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
            throw new LineSessionUnavailableException("EBIR_MES_TEST no configurada.");
        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new SqlCommand("prod.iniciar_paro_operario", connection)
            { CommandType = CommandType.StoredProcedure, CommandTimeout = 10 };
            command.Parameters.Add("@sesion_linea_id", SqlDbType.BigInt).Value = request.LineSessionId;
            command.Parameters.Add("@empleado_id", SqlDbType.BigInt).Value = request.EmployeeId;
            command.Parameters.Add("@motivo", SqlDbType.NVarChar, 30).Value = request.Reason;
            command.Parameters.Add("@correlacion_id", SqlDbType.UniqueIdentifier).Value = request.CorrelationId;
            var id = command.Parameters.Add("@paro_operario_id", SqlDbType.BigInt);
            id.Direction = ParameterDirection.Output;
            var resources = command.Parameters.Add("@recursos_activos", SqlDbType.Int);
            resources.Direction = ParameterDirection.Output;
            await command.ExecuteNonQueryAsync(cancellationToken);
            return new(Convert.ToInt64(id.Value), Convert.ToInt32(resources.Value));
        }
        catch (OperationCanceledException) { throw; }
        catch (SqlException ex) when (TryTranslate(ex.Number, out var rejection))
        { throw new LineSessionRejectedException(rejection.Code, rejection.Message, ex); }
        catch (SqlException ex)
        { throw new LineSessionUnavailableException("No se pudo iniciar el paro.", ex); }
        catch (Exception ex) when (ex is ArgumentException or InvalidOperationException)
        { throw new LineSessionUnavailableException("Configuración no válida.", ex); }
    }

    internal static bool TryTranslate(int number, out (string Code, string Message) rejection)
    {
        rejection = number switch
        {
            52200 => ("CORRELATION_ID_REQUIRED", "La correlación es obligatoria."),
            52201 => ("STOP_REASON_INVALID", "El motivo debe ser WC o PAUSA_CALOR."),
            52202 => ("EMPLOYEE_NOT_ACTIVE_OPERATOR", "El paro requiere un operario activo."),
            52203 => ("LINE_SESSION_NOT_FOUND", "La sesión no existe."),
            52204 => ("ORDER_STATE_NOT_ALLOWED_FOR_STOP", "La orden no admite el paro."),
            52205 => ("LINE_SESSION_NOT_ACTIVE", "La sesión no está activa."),
            52206 => ("LINE_SESSION_CHANGED", "La sesión cambió durante la operación."),
            52207 => ("LINE_SESSION_STATE_NOT_ALLOWED_FOR_STOP", "La sesión no admite el paro."),
            52208 => ("LINE_SESSION_MISMATCH", "La línea no corresponde a la sesión."),
            52209 => ("LINE_STATE_NOT_ALLOWED_FOR_STOP", "La línea no admite el paro."),
            52210 => ("EMPLOYEE_TIME_ENTRY_NOT_OPEN", "El operario no tiene fichaje abierto."),
            52211 => ("OPERATOR_STOP_ALREADY_OPEN", "El fichaje ya tiene un paro abierto."),
            52212 => ("EMPLOYEE_IS_ACTIVE_SUBSTITUTE", "El empleado actúa como sustituto."),
            52213 => ("EMPLOYEE_ROLE_CHANGED", "El empleado dejó de ser operario activo."),
            _ => default
        };
        return rejection != default;
    }
}
