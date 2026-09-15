using System.Data;
using Ebir.Mes.Application.ProductionDashboard;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.ProductionDashboard;

public sealed class SqlLineSupervisorAssignmentWriter(string? connectionString)
    : ILineSupervisorAssignmentWriter
{
    public async Task SetAsync(
        long supervisorEmployeeId,
        IReadOnlyCollection<long> lineIds,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
            throw new ProductionDashboardUnavailableException(
                "La conexion de EBIR_MES_TEST no esta configurada.");

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new SqlCommand("cfg.asignar_mesas_propias", connection)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 10
            };
            command.Parameters.Add("@empleado_id", SqlDbType.BigInt).Value = supervisorEmployeeId;
            command.Parameters.Add("@lineas_csv", SqlDbType.NVarChar, -1).Value =
                string.Join(",", lineIds);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }
        catch (OperationCanceledException) { throw; }
        catch (SqlException ex) when (TryTranslate(ex.Number, out var rejection))
        {
            throw new LineSupervisorAssignmentRejectedException(rejection.Code, rejection.Message);
        }
        catch (SqlException exception)
        {
            throw new ProductionDashboardUnavailableException(
                "No se ha podido guardar la seleccion de mesas.", exception);
        }
        catch (Exception exception)
            when (exception is ArgumentException or InvalidOperationException)
        {
            throw new ProductionDashboardUnavailableException(
                "La conexion de EBIR_MES_TEST no tiene una configuracion valida.", exception);
        }
    }

    internal static bool TryTranslate(int number, out (string Code, string Message) rejection)
    {
        rejection = number switch
        {
            57000 => ("SUPERVISOR_REQUIRED", "El jefe de linea es obligatorio."),
            57001 => ("EMPLOYEE_NOT_ACTIVE_SUPERVISOR", "El empleado no es un jefe de linea vigente."),
            57002 => ("LINE_LIST_INVALID", "La lista de lineas no es valida."),
            57003 => ("LINE_NOT_ACTIVE", "Una linea seleccionada no existe o no esta activa."),
            57004 => ("LINE_ASSIGNMENT_LOCKED", "Una linea seleccionada ya tiene un jefe vigente distinto."),
            _ => default
        };
        return rejection != default;
    }
}
