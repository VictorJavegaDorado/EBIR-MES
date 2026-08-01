using System.Data;
using Ebir.Mes.Application.ProductionOrders;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.ProductionOrders;

public sealed class SqlProductionOrderSelectionReader(string? connectionString)
    : IProductionOrderSelectionReader
{
    private const string Query = """
        SELECT TOP (100)
            orden_id, numero_orden, producto_codigo, producto_descripcion, lote,
            cantidad_objetivo, cantidad_buena_acumulada,
            cantidad_reservada_activa, cantidad_scrap_acumulada,
            tiempo_ejecucion_nav_min, estado, importada_utc
        FROM prod.ordenes
        WHERE estado IN (N'IMPORTADA', N'ABIERTA', N'PICO_PENDIENTE')
        ORDER BY importada_utc DESC, orden_id DESC;
        """;

    public async Task<IReadOnlyList<ProductionOrderSelectionRecord>> ReadAsync(
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            throw new ProductionOrderSelectionUnavailableException(
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
            var orders = new List<ProductionOrderSelectionRecord>();
            await using var reader = await command.ExecuteReaderAsync(
                CommandBehavior.SingleResult,
                cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                orders.Add(new(
                    reader.GetInt64(0), reader.GetString(1), reader.GetString(2),
                    reader.GetString(3), reader.GetString(4), reader.GetInt32(5),
                    reader.GetInt32(6), reader.GetInt32(7), reader.GetInt32(8),
                    reader.GetDecimal(9), reader.GetString(10), reader.GetDateTime(11)));
            }

            return orders;
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (SqlException exception)
        {
            throw new ProductionOrderSelectionUnavailableException(
                "No se han podido consultar las órdenes de producción.", exception);
        }
        catch (Exception exception)
            when (exception is ArgumentException or InvalidOperationException)
        {
            throw new ProductionOrderSelectionUnavailableException(
                "La conexión de EBIR_MES_TEST no tiene una configuración válida.",
                exception);
        }
    }
}
