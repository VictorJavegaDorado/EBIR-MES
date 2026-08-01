using System.Data;
using Ebir.Mes.Application.Rfid;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.Rfid;

public sealed class SqlRfidEmployeeReader(string? connectionString) : IRfidEmployeeReader
{
    private const string Query = """
        SELECT e.empleado_id, e.codigo_nav, e.nombre_completo
        FROM seg.credenciales_rfid c
        JOIN seg.empleados e ON e.empleado_id = c.empleado_id
        WHERE c.rfid_busqueda = @fingerprint
          AND c.activa = 1 AND c.hasta_utc IS NULL
          AND e.activo_nav = 1 AND e.activo_mes = 1;
        """;

    public async Task<RfidEmployeeRecord?> ReadAsync(
        byte[] credentialFingerprint,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
            throw new RfidIdentificationUnavailableException(
                "La conexión de EBIR_MES_TEST no está configurada.");
        if (credentialFingerprint.Length != 32)
            throw new ArgumentException("RFID fingerprints must contain 32 bytes.", nameof(credentialFingerprint));
        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new SqlCommand(Query, connection)
            {
                CommandType = CommandType.Text,
                CommandTimeout = 5
            };
            command.Parameters.Add("@fingerprint", SqlDbType.VarBinary, 32).Value = credentialFingerprint;
            await using var reader = await command.ExecuteReaderAsync(
                CommandBehavior.SingleRow,
                cancellationToken);
            return await reader.ReadAsync(cancellationToken)
                ? new(reader.GetInt64(0), reader.GetString(1), reader.GetString(2))
                : null;
        }
        catch (OperationCanceledException) { throw; }
        catch (SqlException exception)
        {
            throw new RfidIdentificationUnavailableException(
                "No se ha podido resolver la credencial RFID.", exception);
        }
    }
}
