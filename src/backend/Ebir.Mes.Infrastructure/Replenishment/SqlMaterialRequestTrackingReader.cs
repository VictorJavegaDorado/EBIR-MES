using System.Data;
using Ebir.Mes.Application.Replenishment;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.Replenishment;

public sealed class SqlMaterialRequestTrackingReader(string? connectionString)
    : IMaterialRequestTrackingReader
{
    private const string Query = """
        SELECT TOP (10)
               r.solicitud_id,
               a.correlacion_id,
               c.codigo_componente,
               c.descripcion,
               r.cantidad_solicitada,
               r.solicitada_utc
        FROM [log].solicitudes_reaprovisionamiento r
        INNER JOIN nav.componentes_orden c
          ON c.componente_orden_id = r.componente_orden_id
        INNER JOIN aud.eventos a
          ON a.entidad = N'log.solicitudes_reaprovisionamiento'
         AND a.entidad_id = r.solicitud_id
         AND a.tipo_evento = N'REAPROVISIONAMIENTO_SOLICITADO'
        WHERE r.sesion_linea_id = @sesion_linea_id
        ORDER BY r.solicitada_utc DESC, r.solicitud_id DESC;
        """;

    public async Task<IReadOnlyList<MaterialRequestTrackingRecord>> ReadAsync(
        long lineSessionId,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
            throw new MaterialRequestUnavailableException(
                "La conexión MES no está configurada.");
        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new SqlCommand(Query, connection)
            { CommandType = CommandType.Text, CommandTimeout = 5 };
            command.Parameters.Add("@sesion_linea_id", SqlDbType.BigInt).Value = lineSessionId;
            var result = new List<MaterialRequestTrackingRecord>();
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
                result.Add(new(
                    reader.GetInt64(0),
                    reader.GetGuid(1),
                    reader.GetString(2),
                    reader.GetString(3),
                    reader.GetInt32(4),
                    reader.GetDateTime(5)));
            return result;
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception exception)
            when (exception is SqlException or InvalidOperationException or ArgumentException)
        {
            throw new MaterialRequestUnavailableException(
                "No se puede consultar el seguimiento local de material.", exception);
        }
    }
}
