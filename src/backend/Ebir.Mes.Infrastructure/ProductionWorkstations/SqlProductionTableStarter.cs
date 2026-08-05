using System.Data;
using Ebir.Mes.Application.ProductionWorkstations;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.ProductionWorkstations;

public sealed class SqlProductionTableStarter(string? connectionString)
    : IProductionTableStarter
{
    public async Task<ProductionTableStartRecord> StartOrJoinAsync(
        StartOrJoinProductionTableCommand request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            throw new ProductionTableUnavailableException(
                "La conexión de EBIR_MES_TEST no está configurada.");
        }

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new SqlCommand(
                "prod.iniciar_o_incorporar_mesa",
                connection)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 10
            };
            command.Parameters.Add("@orden_id", SqlDbType.BigInt).Value = request.OrderId;
            command.Parameters.Add("@linea_id", SqlDbType.BigInt).Value = request.LineId;
            command.Parameters.Add("@empleado_id", SqlDbType.BigInt).Value = request.EmployeeId;
            command.Parameters.Add("@correlacion_id", SqlDbType.UniqueIdentifier).Value =
                request.CorrelationId;

            var sessionId = Output(command, "@sesion_linea_id", SqlDbType.BigInt);
            var timeEntryId = Output(command, "@fichaje_id", SqlDbType.BigInt);
            var palletReservationId = Output(command, "@reserva_palet_id", SqlDbType.BigInt);
            var sessionCreated = Output(command, "@sesion_creada", SqlDbType.Bit);

            await command.ExecuteNonQueryAsync(cancellationToken);

            return new ProductionTableStartRecord(
                ToInt64(sessionId.Value),
                ToInt64(timeEntryId.Value),
                palletReservationId.Value is DBNull
                    ? null
                    : ToInt64(palletReservationId.Value),
                Convert.ToBoolean(
                    sessionCreated.Value,
                    System.Globalization.CultureInfo.InvariantCulture));
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (SqlException exception) when (TryTranslate(exception.Number, out var rejection))
        {
            throw new ProductionTableRejectedException(
                rejection.Code,
                rejection.Message,
                exception);
        }
        catch (SqlException exception)
        {
            throw new ProductionTableUnavailableException(
                "No se ha podido iniciar o actualizar la mesa de producción.",
                exception);
        }
        catch (Exception exception)
            when (exception is ArgumentException or InvalidOperationException)
        {
            throw new ProductionTableUnavailableException(
                "La conexión de EBIR_MES_TEST no tiene una configuración válida.",
                exception);
        }
    }

    private static SqlParameter Output(
        SqlCommand command,
        string name,
        SqlDbType type)
    {
        var parameter = command.Parameters.Add(name, type);
        parameter.Direction = ParameterDirection.Output;
        return parameter;
    }

    private static long ToInt64(object value) =>
        Convert.ToInt64(value, System.Globalization.CultureInfo.InvariantCulture);

    internal static bool TryTranslate(
        int sqlErrorNumber,
        out (string Code, string Message) rejection)
    {
        rejection = sqlErrorNumber switch
        {
            52700 => ("EMPLOYEE_NOT_ACTIVE_OPERATOR",
                "La mesa requiere un operario productivo activo."),
            52701 => ("PRODUCTION_START_OUTSIDE_SCHEDULE",
                "La producción solo puede iniciarse entre las 06:00 y las 22:00."),
            52702 => ("ACTIVE_SHIFT_NOT_FOUND",
                "No existe un turno activo para el momento del inicio."),
            52703 => ("ORDER_NOT_AVAILABLE",
                "La orden no está disponible para iniciar producción."),
            52704 => ("LINE_NOT_ACTIVE", "La línea no existe o no está activa."),
            52705 => ("LINE_STATE_NOT_INITIALIZED",
                "La línea no dispone de estado operativo inicial."),
            52706 => ("LINE_BUSY_WITH_ANOTHER_ORDER",
                "La línea está ocupada por otra orden."),
            52707 => ("PALLET_FORMAT_NOT_AVAILABLE",
                "La orden no tiene un único formato de palé POK activo y predeterminado."),
            52708 => ("ORDER_SESSION_ALREADY_ACTIVE",
                "La orden ya está activa en otra línea."),
            52709 => ("CORRELATION_CONFLICT",
                "La correlación ya pertenece a otra operación de mesa."),
            52710 => ("PRODUCTION_TABLE_LOCK_UNAVAILABLE",
                "La mesa está ocupada; vuelve a intentar la identificación."),
            51800 => ("EMPLOYEE_NOT_ACTIVE_OPERATOR",
                "La entrada requiere un operario productivo activo."),
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
                "El operario ya está produciendo en una mesa."),
            51809 => ("NO_PENDING_QUANTITY_FOR_PRODUCTION",
                "No queda cantidad pendiente para iniciar la producción."),
            51810 => ("EMPLOYEE_ROLE_CHANGED",
                "El empleado ya no es un operario productivo activo."),
            _ => default
        };

        return rejection != default;
    }
}
