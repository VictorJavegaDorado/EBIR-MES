using System.Data;
using Ebir.Mes.Application.LineIdentification;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.LineIdentification;

public sealed class SqlLineIdentificationReader(string? connectionString)
    : ILineIdentificationReader
{
    private const string Query = """
        SELECT
            l.linea_id,
            l.codigo,
            l.nombre,
            c.codigo AS centro_codigo,
            c.nombre AS centro_nombre,
            l.activa,
            COALESCE(e.estado, N'LIBRE') AS estado_operativo
        FROM cfg.lineas AS l
        INNER JOIN cfg.centros_trabajo AS c
            ON c.centro_trabajo_id = l.centro_trabajo_id
        LEFT JOIN prod.estados_linea AS e
            ON e.linea_id = l.linea_id
        WHERE UPPER(LTRIM(RTRIM(l.codigo))) = @codigo
        ORDER BY c.codigo, l.linea_id;
        """;

    public async Task<IReadOnlyList<LineIdentificationRecord>> FindByCodeAsync(
        string normalizedCode,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            throw new LineIdentificationUnavailableException(
                "La conexión de EBIR_MES_TEST no está configurada.");
        }

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            await using var command = new SqlCommand(Query, connection)
            {
                CommandType = CommandType.Text,
                CommandTimeout = 5
            };
            command.Parameters.Add(
                new SqlParameter("@codigo", SqlDbType.NVarChar, IdentifyLine.MaximumCodeLength)
                {
                    Value = normalizedCode
                });

            var matches = new List<LineIdentificationRecord>();
            await using var reader = await command.ExecuteReaderAsync(
                CommandBehavior.SingleResult,
                cancellationToken);

            while (await reader.ReadAsync(cancellationToken))
            {
                matches.Add(new LineIdentificationRecord(
                    reader.GetInt64(0),
                    reader.GetString(1),
                    reader.GetString(2),
                    reader.GetString(3),
                    reader.GetString(4),
                    reader.GetBoolean(5),
                    reader.GetString(6)));
            }

            return matches;
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (LineIdentificationUnavailableException)
        {
            throw;
        }
        catch (SqlException exception)
        {
            throw new LineIdentificationUnavailableException(
                "No se ha podido consultar el estado de la línea.",
                exception);
        }
        catch (Exception exception)
            when (exception is ArgumentException or InvalidOperationException)
        {
            throw new LineIdentificationUnavailableException(
                "La conexión de EBIR_MES_TEST no tiene una configuración válida.",
                exception);
        }
    }
}
