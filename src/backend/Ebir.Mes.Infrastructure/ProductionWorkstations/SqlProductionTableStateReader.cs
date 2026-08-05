using System.Data;
using Ebir.Mes.Application.ProductionWorkstations;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.ProductionWorkstations;

public sealed class SqlProductionTableStateReader(string? connectionString)
    : IProductionTableStateReader
{
    public async Task<ProductionTableStateRecord?> ReadAsync(
        long orderId,
        long lineId,
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
                "prod.obtener_estado_mesa",
                connection)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 10
            };
            command.Parameters.Add("@orden_id", SqlDbType.BigInt).Value = orderId;
            command.Parameters.Add("@linea_id", SqlDbType.BigInt).Value = lineId;

            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return null;
            }

            var sessionId = reader.GetInt64(0);
            var state = new
            {
                SessionId = sessionId,
                OrderId = reader.GetInt64(1),
                LineId = reader.GetInt64(2),
                State = reader.GetString(3),
                StartedAtUtc = reader.IsDBNull(4) ? (DateTime?)null : AsUtc(reader.GetDateTime(4)),
                ServerTimeUtc = AsUtc(reader.GetDateTime(5)),
                ProductiveSeconds = reader.GetInt64(6),
                ActiveResources = reader.GetInt32(7),
                Capacity = reader.GetDecimal(8),
                FormatCode = reader.GetString(9),
                UnitsPerPallet = reader.GetInt32(10)
            };

            var operators = new List<ProductionTableOperatorRecord>();
            if (await reader.NextResultAsync(cancellationToken))
            {
                while (await reader.ReadAsync(cancellationToken))
                {
                    operators.Add(new ProductionTableOperatorRecord(
                        reader.GetInt64(0),
                        reader.GetString(1),
                        reader.GetString(2),
                        AsUtc(reader.GetDateTime(3)),
                        reader.GetInt64(4),
                        reader.GetString(5)));
                }
            }

            return new ProductionTableStateRecord(
                state.SessionId,
                state.OrderId,
                state.LineId,
                state.State,
                state.StartedAtUtc,
                state.ServerTimeUtc,
                state.ProductiveSeconds,
                state.ActiveResources,
                state.Capacity,
                state.FormatCode,
                state.UnitsPerPallet,
                operators);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (SqlException exception)
        {
            throw new ProductionTableUnavailableException(
                "No se ha podido leer el estado de la mesa de producción.",
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

    private static DateTime AsUtc(DateTime value) =>
        DateTime.SpecifyKind(value, DateTimeKind.Utc);
}
