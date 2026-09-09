using System.Data;
using Ebir.Mes.Application.Rfid;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.Rfid;

public sealed class SqlSupervisorRfidReader(string? connectionString)
    : ISupervisorRfidReader
{
    private const string Query = """
        SELECT TOP (1) e.empleado_id, e.codigo_nav, e.nombre_completo
        FROM seg.credenciales_rfid c
        JOIN seg.empleados e ON e.empleado_id = c.empleado_id
        WHERE c.rfid_busqueda = @fingerprint
          AND c.activa = 1 AND c.hasta_utc IS NULL
          AND e.activo_nav = 1 AND e.activo_mes = 1
          AND EXISTS
          (
              SELECT 1
              FROM seg.empleados_roles er
              JOIN seg.roles r ON r.rol_id = er.rol_id
              WHERE er.empleado_id = e.empleado_id
                AND r.codigo = N'SUPERVISOR' AND r.activo = 1
                AND er.desde_utc <= SYSUTCDATETIME()
                AND (er.hasta_utc IS NULL OR er.hasta_utc > SYSUTCDATETIME())
          );
        """;

    public async Task<RfidEmployeeRecord?> ReadAsync(
        byte[] credentialFingerprint,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
            throw new RfidIdentificationUnavailableException(
                "La conexion de EBIR_MES_TEST no esta configurada.");
        if (credentialFingerprint.Length != 32)
            throw new ArgumentException(
                "RFID fingerprints must contain 32 bytes.",
                nameof(credentialFingerprint));

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new SqlCommand(Query, connection)
            {
                CommandType = CommandType.Text,
                CommandTimeout = 5
            };
            command.Parameters.Add("@fingerprint", SqlDbType.VarBinary, 32).Value =
                credentialFingerprint;
            await using var data = await command.ExecuteReaderAsync(
                CommandBehavior.SingleRow,
                cancellationToken);
            return await data.ReadAsync(cancellationToken)
                ? new(data.GetInt64(0), data.GetString(1), data.GetString(2))
                : null;
        }
        catch (OperationCanceledException) { throw; }
        catch (SqlException exception)
        {
            throw new RfidIdentificationUnavailableException(
                "No se ha podido autorizar el acceso de supervisor.", exception);
        }
    }
}
