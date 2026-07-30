using System.Data;
using Ebir.Mes.Application.LineSessions;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.LineSessions;

public sealed class SqlLineSessionFinisher(string? connectionString)
    : ILineSessionFinisher
{
    public async Task<int> FinishAsync(
        FinishLineSessionCommand request,
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
                "prod.finalizar_sesion_turno",
                connection)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 10
            };
            command.Parameters.Add("@sesion_linea_id", SqlDbType.BigInt).Value =
                request.LineSessionId;
            command.Parameters.Add("@supervisor_id", SqlDbType.BigInt).Value =
                request.SupervisorId;
            command.Parameters.Add("@correlacion_id", SqlDbType.UniqueIdentifier).Value =
                request.CorrelationId;
            var closed = command.Parameters.Add("@fichajes_cerrados", SqlDbType.Int);
            closed.Direction = ParameterDirection.Output;

            await command.ExecuteNonQueryAsync(cancellationToken);
            return Convert.ToInt32(
                closed.Value,
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
                "No se ha podido finalizar la sesión de turno.",
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
            52100 => ("CORRELATION_ID_REQUIRED", "La correlación es obligatoria."),
            52101 => ("SUPERVISOR_NOT_ACTIVE",
                "La finalización requiere un supervisor activo."),
            52102 => ("LINE_SESSION_NOT_FOUND", "La sesión de línea no existe."),
            52103 => ("ORDER_NOT_FOUND", "La orden no existe."),
            52104 => ("LINE_SESSION_NOT_ACTIVE", "La sesión no está activa."),
            52105 => ("LINE_SESSION_CHANGED",
                "La sesión cambió durante la operación; vuelve a intentarlo."),
            52106 => ("LINE_SESSION_STATE_NOT_ALLOWED_FOR_FINISH",
                "El estado de la sesión no admite el fin de turno."),
            52107 => ("LINE_SESSION_MISMATCH",
                "La línea no corresponde a la sesión activa."),
            52108 => ("LINE_STATE_NOT_ALLOWED_FOR_FINISH",
                "El estado de la línea no admite el fin de turno."),
            52109 => ("ACTIVE_PALLET_RESERVATION",
                "La sesión mantiene una reserva de palé activa."),
            52110 => ("PALLET_OUTPUT_PENDING",
                "La sesión mantiene una salida de palé pendiente."),
            52111 => ("PALLET_LABEL_PENDING",
                "La sesión mantiene una etiqueta de palé pendiente."),
            52112 => ("SUPERVISOR_ROLE_CHANGED",
                "El supervisor ha dejado de estar activo."),
            52113 => ("ORDER_STATE_NOT_ALLOWED_FOR_FINISH",
                "El estado de la orden no admite el fin de turno."),
            _ => default
        };
        return rejection != default;
    }
}
