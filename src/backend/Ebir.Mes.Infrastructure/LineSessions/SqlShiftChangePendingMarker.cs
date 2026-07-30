using System.Data;
using Ebir.Mes.Application.LineSessions;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.LineSessions;

public sealed class SqlShiftChangePendingMarker(string? connectionString)
    : IShiftChangePendingMarker
{
    public async Task<bool> MarkAsync(
        MarkShiftChangePendingCommand request,
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
                "prod.marcar_cambio_turno_pendiente",
                connection)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 10
            };
            command.Parameters.Add("@sesion_linea_id", SqlDbType.BigInt).Value =
                request.LineSessionId;
            command.Parameters.Add("@correlacion_id", SqlDbType.UniqueIdentifier).Value =
                request.CorrelationId;
            var changeMarked = command.Parameters.Add(
                "@cambio_marcado",
                SqlDbType.Bit);
            changeMarked.Direction = ParameterDirection.Output;

            await command.ExecuteNonQueryAsync(cancellationToken);
            return Convert.ToBoolean(
                changeMarked.Value,
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
                "No se ha podido marcar el cambio de turno.",
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
            52000 => ("LINE_SESSION_NOT_ACTIVE",
                "La sesión no existe o ya está finalizada."),
            52001 => ("SHIFT_NOT_SUPPORTED",
                "El turno de la sesión no admite el cálculo automático."),
            52002 => ("SHIFT_CHANGE_NOT_REACHED",
                "Todavía no se ha alcanzado el cambio de turno."),
            52003 => ("CORRELATION_ID_REQUIRED",
                "La correlación es obligatoria."),
            _ => default
        };

        return rejection != default;
    }
}
