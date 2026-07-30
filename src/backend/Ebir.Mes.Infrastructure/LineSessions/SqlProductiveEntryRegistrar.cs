using System.Data;
using Ebir.Mes.Application.LineSessions;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.LineSessions;

public sealed class SqlProductiveEntryRegistrar(string? connectionString)
    : IProductiveEntryRegistrar
{
    public async Task<ProductiveEntryRecord> RegisterAsync(
        RegisterProductiveEntryCommand request,
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
                "prod.registrar_entrada_productiva",
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

            var timeEntryId = command.Parameters.Add("@fichaje_id", SqlDbType.BigInt);
            timeEntryId.Direction = ParameterDirection.Output;
            var palletReservationId = command.Parameters.Add(
                "@reserva_palet_id",
                SqlDbType.BigInt);
            palletReservationId.Direction = ParameterDirection.Output;

            await command.ExecuteNonQueryAsync(cancellationToken);

            return new ProductiveEntryRecord(
                Convert.ToInt64(
                    timeEntryId.Value,
                    System.Globalization.CultureInfo.InvariantCulture),
                palletReservationId.Value is DBNull
                    ? null
                    : Convert.ToInt64(
                        palletReservationId.Value,
                        System.Globalization.CultureInfo.InvariantCulture));
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
                "No se ha podido registrar la entrada productiva.",
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
            51800 => ("EMPLOYEE_NOT_ACTIVE_OPERATOR",
                "La entrada requiere un operario productivo activo."),
            51801 => ("LINE_SESSION_NOT_FOUND", "La sesión de línea no existe."),
            51802 => ("ORDER_NOT_AVAILABLE_FOR_ENTRY",
                "La orden no admite una entrada productiva."),
            51803 => ("LINE_SESSION_NOT_ACTIVE",
                "La sesión no está activa o su formato no está disponible."),
            51804 => ("LINE_SESSION_CHANGED",
                "La sesión cambió durante la operación; vuelve a intentarlo."),
            51805 => ("LINE_SESSION_STATE_NOT_ALLOWED",
                "El estado de la sesión no admite una entrada productiva."),
            51806 => ("LINE_SESSION_MISMATCH",
                "La línea no corresponde a la sesión activa."),
            51807 => ("LINE_STATE_NOT_ALLOWED_FOR_ENTRY",
                "El estado de la línea no admite una entrada productiva."),
            51808 => ("EMPLOYEE_TIME_ENTRY_ALREADY_OPEN",
                "El operario ya tiene un fichaje productivo abierto."),
            51809 => ("NO_PENDING_QUANTITY_FOR_PRODUCTION",
                "No queda cantidad pendiente para iniciar la producción."),
            51810 => ("EMPLOYEE_ROLE_CHANGED",
                "El empleado ya no es un operario productivo activo."),
            _ => default
        };

        return rejection != default;
    }
}
