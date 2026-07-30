using System.Data;
using Ebir.Mes.Application.LineSessions;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.LineSessions;

public sealed class SqlProductiveExitRegistrar(string? connectionString)
    : IProductiveExitRegistrar
{
    public async Task<int> RegisterAsync(
        RegisterProductiveExitCommand request,
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
                "prod.registrar_salida_productiva",
                connection)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 10
            };
            command.Parameters.Add("@sesion_linea_id", SqlDbType.BigInt).Value =
                request.LineSessionId;
            command.Parameters.Add("@empleado_id", SqlDbType.BigInt).Value =
                request.EmployeeId;
            command.Parameters.Add("@correlacion_id", SqlDbType.UniqueIdentifier).Value =
                request.CorrelationId;
            var activeResources = command.Parameters.Add(
                "@recursos_activos",
                SqlDbType.Int);
            activeResources.Direction = ParameterDirection.Output;

            await command.ExecuteNonQueryAsync(cancellationToken);
            return Convert.ToInt32(
                activeResources.Value,
                System.Globalization.CultureInfo.InvariantCulture);
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
                "No se ha podido registrar la salida productiva.",
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
        int sqlErrorNumber,
        out (string Code, string Message) rejection)
    {
        rejection = sqlErrorNumber switch
        {
            51900 => ("LINE_SESSION_NOT_FOUND", "La sesión de línea no existe."),
            51901 => ("ORDER_NOT_FOUND", "La orden no existe."),
            51902 => ("LINE_SESSION_NOT_ACTIVE", "La sesión no está activa."),
            51903 => ("LINE_SESSION_CHANGED",
                "La sesión cambió durante la operación; vuelve a intentarlo."),
            51904 => ("LINE_SESSION_STATE_NOT_ALLOWED_FOR_EXIT",
                "El estado de la sesión no admite una salida productiva."),
            51905 => ("LINE_SESSION_MISMATCH",
                "La línea no corresponde a la sesión activa."),
            51906 => ("LINE_STATE_NOT_ALLOWED_FOR_EXIT",
                "El estado de la línea no admite una salida productiva."),
            51907 => ("EMPLOYEE_TIME_ENTRY_NOT_OPEN",
                "El operario no tiene un fichaje productivo abierto en la sesión."),
            51908 => ("EMPLOYEE_STOP_STILL_OPEN",
                "El operario tiene un paro abierto que debe resolverse antes de salir."),
            51909 => ("EMPLOYEE_SUBSTITUTION_STILL_ACTIVE",
                "El empleado participa en una sustitución activa."),
            _ => default
        };

        return rejection != default;
    }
}
