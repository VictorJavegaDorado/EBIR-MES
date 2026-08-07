using System.Data;
using Ebir.Mes.Application.ProductionOrders;
using Ebir.Mes.Application.ProductionWorkstations;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.ProductionWorkstations;

public sealed class SqlProductionTableStateReader(string? connectionString)
    : IProductionTableStateReader
{
    private const string ActiveOrderQuery = """
        SELECT TOP (2)
            o.orden_id, o.numero_orden, o.producto_codigo, o.producto_descripcion,
            o.lote, o.cantidad_objetivo, o.cantidad_buena_acumulada,
            o.cantidad_reservada_activa, o.cantidad_scrap_acumulada,
            o.tiempo_ejecucion_nav_min, o.estado, o.importada_utc
        FROM prod.sesiones_linea s
        JOIN prod.ordenes o ON o.orden_id = s.orden_id
        WHERE s.linea_id = @linea_id
          AND s.finalizada_utc IS NULL
        ORDER BY s.sesion_linea_id DESC;
        """;

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
            return await ReadStateAsync(connection, orderId, lineId, cancellationToken);
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

    public async Task<ActiveProductionTableRecord?> ReadActiveByLineAsync(
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
            await using var command = new SqlCommand(ActiveOrderQuery, connection)
            {
                CommandType = CommandType.Text,
                CommandTimeout = 5
            };
            command.Parameters.Add("@linea_id", SqlDbType.BigInt).Value = lineId;

            ProductionOrderSelectionRecord? order;
            await using (var reader = await command.ExecuteReaderAsync(
                CommandBehavior.SingleResult,
                cancellationToken))
            {
                if (!await reader.ReadAsync(cancellationToken))
                {
                    return null;
                }

                order = ReadOrder(reader);
                if (await reader.ReadAsync(cancellationToken))
                {
                    throw new ProductionTableUnavailableException(
                        "La línea tiene más de una mesa activa.");
                }
            }

            var table = await ReadStateAsync(
                connection,
                order.ProductionOrderId,
                lineId,
                cancellationToken);
            return table is null ? null : new ActiveProductionTableRecord(order, table);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (ProductionTableUnavailableException)
        {
            throw;
        }
        catch (SqlException exception)
        {
            throw new ProductionTableUnavailableException(
                "No se ha podido recuperar la mesa activa de la línea.",
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

    private static async Task<ProductionTableStateRecord?> ReadStateAsync(
        SqlConnection connection,
        long orderId,
        long lineId,
        CancellationToken cancellationToken)
    {
        await using var command = new SqlCommand("prod.obtener_estado_mesa", connection)
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

        var state = new
        {
            SessionId = reader.GetInt64(0),
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

    private static ProductionOrderSelectionRecord ReadOrder(SqlDataReader reader) =>
        new(
            reader.GetInt64(0),
            reader.GetString(1),
            reader.GetString(2),
            reader.GetString(3),
            reader.GetString(4),
            reader.GetInt32(5),
            reader.GetInt32(6),
            reader.GetInt32(7),
            reader.GetInt32(8),
            reader.GetDecimal(9),
            reader.GetString(10),
            AsUtc(reader.GetDateTime(11)));

    private static DateTime AsUtc(DateTime value) =>
        DateTime.SpecifyKind(value, DateTimeKind.Utc);
}
