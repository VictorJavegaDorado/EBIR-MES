using System.Data;
using Ebir.Mes.Application.LineSessions;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.LineSessions;

public sealed class SqlLineSessionOpener(string? connectionString) : ILineSessionOpener
{
    public async Task<long> OpenAsync(
        OpenLineSessionCommand request,
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
            await using var command = new SqlCommand("prod.abrir_sesion_linea", connection)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 10
            };
            command.Parameters.Add("@orden_id", SqlDbType.BigInt).Value = request.OrderId;
            command.Parameters.Add("@linea_id", SqlDbType.BigInt).Value = request.LineId;
            command.Parameters.Add("@formato_palet_orden_id", SqlDbType.BigInt).Value =
                request.PalletFormatOrderId;
            command.Parameters.Add("@supervisor_id", SqlDbType.BigInt).Value =
                request.SupervisorId;
            command.Parameters.Add("@inicio_fuera_horario_confirmado", SqlDbType.Bit).Value =
                request.OutsideScheduleConfirmed;
            command.Parameters.Add("@correlacion_id", SqlDbType.UniqueIdentifier).Value =
                request.CorrelationId;
            var sessionId = command.Parameters.Add("@sesion_linea_id", SqlDbType.BigInt);
            sessionId.Direction = ParameterDirection.Output;

            await command.ExecuteNonQueryAsync(cancellationToken);
            return Convert.ToInt64(
                sessionId.Value,
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
                "No se ha podido abrir la sesión de línea.",
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
            51700 => ("SUPERVISOR_NOT_ACTIVE", "La apertura requiere un supervisor activo."),
            51701 => ("OUTSIDE_SCHEDULE_CONFIRMATION_REQUIRED",
                "Confirma explícitamente el inicio fuera del horario habitual."),
            51702 => ("ACTIVE_SHIFT_NOT_FOUND",
                "No existe un turno activo para el momento de la apertura."),
            51703 => ("LINE_NOT_ACTIVE", "La línea no existe o no está activa."),
            51704 => ("LINE_STATE_NOT_INITIALIZED",
                "La línea no dispone de estado operativo inicial."),
            51705 => ("LINE_NOT_AVAILABLE", "La línea no está libre para abrir una sesión."),
            51706 => ("ORDER_NOT_FOUND", "La orden no existe."),
            51707 => ("ORDER_STATE_NOT_ALLOWED",
                "El estado de la orden no permite abrir una sesión."),
            51708 => ("PALLET_FORMAT_NOT_AVAILABLE",
                "El formato de palé no pertenece a la orden o no está activo."),
            51709 => ("LINE_SESSION_ALREADY_ACTIVE",
                "La línea ya tiene una sesión activa."),
            51710 => ("ORDER_SESSION_ALREADY_ACTIVE",
                "La orden ya tiene una sesión activa."),
            _ => default
        };

        return rejection != default;
    }
}
