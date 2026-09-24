using System.Data;
using Ebir.Mes.Application.Replenishment;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.Replenishment;

public sealed class SqlMaterialRequestOptionsReader(string? connectionString)
    : IMaterialRequestOptionsReader
{
    private const string Query = """
        SELECT c.componente_orden_id, o.numero_orden, c.codigo_componente,
               c.descripcion, c.unidad_medida, c.cantidad_teorica,
               COUNT(CASE WHEN r.estado IN (N'PENDIENTE',N'ACEPTADA',N'EN_CAMINO') THEN 1 END)
        FROM prod.sesiones_linea s
        INNER JOIN prod.ordenes o ON o.orden_id = s.orden_id
        INNER JOIN nav.componentes_orden c ON c.orden_id = s.orden_id
        LEFT JOIN [log].solicitudes_reaprovisionamiento r
          ON r.sesion_linea_id = s.sesion_linea_id
         AND r.componente_orden_id = c.componente_orden_id
        WHERE s.sesion_linea_id = @sesion_linea_id
          AND s.finalizada_utc IS NULL
        GROUP BY c.componente_orden_id, o.numero_orden, c.codigo_componente,
                 c.descripcion, c.unidad_medida, c.cantidad_teorica
        ORDER BY c.codigo_componente;
        """;

    public async Task<IReadOnlyList<MaterialRequestOption>> ReadAsync(
        long lineSessionId, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
            throw new MaterialRequestUnavailableException("La conexión MES no está configurada.");
        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new SqlCommand(Query, connection)
            { CommandType = CommandType.Text, CommandTimeout = 5 };
            command.Parameters.Add("@sesion_linea_id", SqlDbType.BigInt).Value = lineSessionId;
            var result = new List<MaterialRequestOption>();
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
                result.Add(new(reader.GetInt64(0), reader.GetString(1), reader.GetString(2),
                    reader.GetString(3), reader.IsDBNull(4) ? null : reader.GetString(4),
                    reader.IsDBNull(5) ? null : reader.GetDecimal(5), reader.GetInt32(6)));
            return result;
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception exception) when (exception is SqlException or InvalidOperationException or ArgumentException)
        {
            throw new MaterialRequestUnavailableException("No se pueden consultar los componentes.", exception);
        }
    }
}
