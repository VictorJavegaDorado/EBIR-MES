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

    private const string CapacityMetricsQuery = """
        DECLARE @ahora_utc datetime2(3) = SYSUTCDATETIME();

        SELECT
            COALESCE(SUM(
                CONVERT(decimal(38,10), tc.capacidad_teorica_hora)
                * CONVERT(decimal(38,10), DATEDIFF_BIG(
                    MILLISECOND, tc.inicio_utc, COALESCE(tc.fin_utc, @ahora_utc)))
                / CONVERT(decimal(38,10), 3600000)), 0) AS unidades_teoricas_acumuladas,
            COALESCE(SUM(
                CONVERT(bigint, tc.recursos_activos)
                * DATEDIFF_BIG(SECOND, tc.inicio_utc, COALESCE(tc.fin_utc, @ahora_utc))), 0)
                AS segundos_recurso
        FROM prod.tramos_capacidad tc
        WHERE tc.sesion_linea_id = @sesion_linea_id;
        """;

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

        long sessionId;
        long stateOrderId;
        long stateLineId;
        string state;
        DateTime? startedAtUtc;
        DateTime serverTimeUtc;
        long productiveSeconds;
        int activeResources;
        decimal capacity;
        string formatCode;
        int unitsPerPallet;
        var operators = new List<ProductionTableOperatorRecord>();

        await using (var reader = await command.ExecuteReaderAsync(cancellationToken))
        {
            if (!await reader.ReadAsync(cancellationToken))
            {
                return null;
            }

            sessionId = reader.GetInt64(0);
            stateOrderId = reader.GetInt64(1);
            stateLineId = reader.GetInt64(2);
            state = reader.GetString(3);
            startedAtUtc = reader.IsDBNull(4) ? (DateTime?)null : AsUtc(reader.GetDateTime(4));
            serverTimeUtc = AsUtc(reader.GetDateTime(5));
            productiveSeconds = reader.GetInt64(6);
            activeResources = reader.GetInt32(7);
            capacity = reader.GetDecimal(8);
            formatCode = reader.GetString(9);
            unitsPerPallet = reader.GetInt32(10);

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
        }

        var (theoreticalUnitsToDate, resourceSeconds) = await ReadCapacityMetricsAsync(
            connection,
            sessionId,
            cancellationToken);

        return new ProductionTableStateRecord(
            sessionId,
            stateOrderId,
            stateLineId,
            state,
            startedAtUtc,
            serverTimeUtc,
            productiveSeconds,
            activeResources,
            capacity,
            formatCode,
            unitsPerPallet,
            operators,
            TheoreticalUnitsToDate: theoreticalUnitsToDate,
            ResourceSeconds: resourceSeconds);
    }

    private static async Task<(decimal TheoreticalUnits, long ResourceSeconds)> ReadCapacityMetricsAsync(
        SqlConnection connection,
        long sessionId,
        CancellationToken cancellationToken)
    {
        await using var command = new SqlCommand(CapacityMetricsQuery, connection)
        {
            CommandType = CommandType.Text,
            CommandTimeout = 10
        };
        command.Parameters.Add("@sesion_linea_id", SqlDbType.BigInt).Value = sessionId;

        await using var reader = await command.ExecuteReaderAsync(
            CommandBehavior.SingleRow,
            cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return (0m, 0);
        }

        return (reader.GetDecimal(0), reader.GetInt64(1));
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
