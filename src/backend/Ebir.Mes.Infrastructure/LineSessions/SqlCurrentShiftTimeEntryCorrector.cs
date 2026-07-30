using System.Data;
using Ebir.Mes.Application.LineSessions;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.LineSessions;

public sealed class SqlCurrentShiftTimeEntryCorrector(string? connectionString)
    : ICurrentShiftTimeEntryCorrector
{
    public async Task CorrectAsync(
        CorrectCurrentShiftTimeEntryCommand request,
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
                "prod.corregir_fichaje_turno_actual",
                connection)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 10
            };
            command.Parameters.Add("@fichaje_id", SqlDbType.BigInt).Value =
                request.TimeEntryId;
            var correctedEntry =
                command.Parameters.Add("@entrada_utc_corregida", SqlDbType.DateTime2);
            correctedEntry.Scale = 3;
            correctedEntry.Value = request.CorrectedEntryUtc.UtcDateTime;
            var correctedExit =
                command.Parameters.Add("@salida_utc_corregida", SqlDbType.DateTime2);
            correctedExit.Scale = 3;
            correctedExit.Value = request.CorrectedExitUtc is null
                ? DBNull.Value
                : request.CorrectedExitUtc.Value.UtcDateTime;
            command.Parameters.Add("@supervisor_id", SqlDbType.BigInt).Value =
                request.SupervisorId;
            command.Parameters.Add(
                "@motivo",
                SqlDbType.NVarChar,
                CorrectCurrentShiftTimeEntry.MaximumReasonLength).Value = request.Reason;
            command.Parameters.Add("@correlacion_id", SqlDbType.UniqueIdentifier).Value =
                request.CorrelationId;
            await command.ExecuteNonQueryAsync(cancellationToken);
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
                "No se ha podido corregir el fichaje.", exception);
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
            52600 => ("CORRELATION_ID_REQUIRED", "La correlación es obligatoria."),
            52601 => ("CORRECTED_ENTRY_UTC_REQUIRED", "La entrada corregida es obligatoria."),
            52602 => ("CORRECTED_EXIT_BEFORE_ENTRY",
                "La salida corregida no puede ser anterior a la entrada."),
            52603 => ("TIME_ENTRY_CORRECTION_REASON_REQUIRED",
                "El motivo de corrección es obligatorio."),
            52604 => ("SUPERVISOR_NOT_ACTIVE", "La corrección requiere supervisor activo."),
            52605 => ("TIME_ENTRY_NOT_FOUND", "El fichaje no existe."),
            52606 => ("TIME_ENTRY_LINE_SESSION_NOT_FOUND", "La sesión no existe."),
            52607 => ("FUTURE_TIME_ENTRY_CORRECTION_NOT_ALLOWED",
                "La corrección no admite instantes futuros."),
            52608 => ("ORDER_NOT_FOUND", "La orden no existe."),
            52609 => ("LINE_SESSION_NOT_ACTIVE", "La sesión no está activa."),
            52610 => ("LINE_SESSION_CHANGED", "La sesión cambió durante la operación."),
            52611 => ("LINE_SESSION_STATE_NOT_ALLOWED_FOR_TIME_ENTRY_CORRECTION",
                "La sesión no admite corregir fichajes."),
            52612 => ("CORRECTED_ENTRY_BEFORE_LINE_SESSION_LOAD",
                "La entrada corregida precede a la carga de la sesión."),
            52613 => ("LINE_SESSION_MISMATCH", "La línea no corresponde a la sesión."),
            52614 => ("TIME_ENTRY_CHANGED", "El fichaje cambió durante la operación."),
            52615 => ("EMPLOYEE_HAS_ANOTHER_OPEN_TIME_ENTRY",
                "El empleado ya tiene otro fichaje abierto."),
            52616 => ("TIME_ENTRY_INTERVAL_OVERLAP",
                "El intervalo corregido solapa otro fichaje."),
            52617 => ("OPERATOR_STOP_OUTSIDE_CORRECTED_TIME_ENTRY",
                "La corrección dejaría un paro fuera del fichaje."),
            52618 => ("CAPACITY_SUBSTITUTION_OUTSIDE_CORRECTED_TIME_ENTRY",
                "La corrección dejaría una sustitución fuera del fichaje."),
            52619 => ("ACTIVE_CAPACITY_SUBSTITUTION_PREVENTS_TIME_ENTRY_CORRECTION",
                "Una sustitución activa impide corregir el fichaje."),
            52620 => ("CORRECTING_SUPERVISOR_ROLE_CHANGED",
                "El corrector dejó de ser supervisor activo."),
            52621 => ("LINE_SESSION_HAS_NO_TIME_ENTRIES",
                "La sesión no conserva fichajes para reconstruir."),
            _ => default
        };
        return rejection != default;
    }
}
