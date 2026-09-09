using System.Data;
using Ebir.Mes.Application.Printing.LabelControl;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.Printing;

public sealed class SqlLabelControlReader(string? connectionString) : ILabelControlReader
{
    private const string Query = """
        WITH recent_orders AS
        (
            SELECT TOP (50) p.orden_id, MAX(p.cerrado_utc) AS ultimo_cierre_utc
            FROM prod.palets p
            WHERE p.estado=N'CERRADO'
            GROUP BY p.orden_id
            ORDER BY MAX(p.cerrado_utc) DESC, p.orden_id DESC
        )
        SELECT
            o.orden_id,o.numero_orden,o.producto_codigo,o.producto_descripcion,o.estado,
            l.linea_id,l.codigo,l.nombre,ro.ultimo_cierre_utc,
            p.palet_id,p.numero_palet,p.cantidad_buena,p.es_ultimo,p.cerrado_utc,
            n.operacion_nav_id,n.estado,
            e.etiqueta_id,e.estado,
            j.trabajo_impresion_id,j.estado,COALESCE(j.numero_intentos,0),
            CONVERT(bit,CASE WHEN
                n.estado IN (N'ERROR_DEFINITIVO',N'RESULTADO_DESCONOCIDO')
                OR e.estado=N'ERROR'
                OR j.estado IN (N'ERROR',N'RESULTADO_DESCONOCIDO')
                OR EXISTS
                (
                    SELECT 1 FROM nav.intentos_operacion ni
                    WHERE ni.operacion_nav_id=n.operacion_nav_id
                      AND ni.resultado IN
                          (N'ERROR_REINTENTABLE',N'ERROR_DEFINITIVO',N'RESULTADO_DESCONOCIDO')
                )
                OR EXISTS
                (
                    SELECT 1 FROM imp.intentos_impresion ii
                    JOIN imp.trabajos_impresion tj
                      ON tj.trabajo_impresion_id=ii.trabajo_impresion_id
                    WHERE tj.etiqueta_id=e.etiqueta_id
                      AND ii.resultado IN (N'ERROR',N'RESULTADO_DESCONOCIDO')
                )
                THEN 1 ELSE 0 END) AS tuvo_incidencia,
            CONVERT(bit,CASE WHEN
                e.estado=N'IMPRESA'
                AND EXISTS
                (
                    SELECT 1 FROM imp.trabajos_impresion original
                    WHERE original.etiqueta_id=e.etiqueta_id
                      AND original.es_reimpresion=0 AND original.estado=N'COMPLETADO'
                )
                AND NOT EXISTS
                (
                    SELECT 1 FROM imp.trabajos_impresion abierto
                    WHERE abierto.etiqueta_id=e.etiqueta_id
                      AND abierto.estado IN (N'PENDIENTE',N'PROCESANDO')
                )
                THEN 1 ELSE 0 END) AS puede_reimprimir
        FROM recent_orders ro
        JOIN prod.ordenes o ON o.orden_id=ro.orden_id
        JOIN prod.palets p ON p.orden_id=o.orden_id AND p.estado=N'CERRADO'
        JOIN prod.sesiones_linea s ON s.sesion_linea_id=p.sesion_linea_id
        JOIN cfg.lineas l ON l.linea_id=s.linea_id
        OUTER APPLY
        (
            SELECT TOP (1) x.operacion_nav_id,x.estado
            FROM nav.operaciones x
            WHERE x.orden_id=o.orden_id AND x.palet_id=p.palet_id
              AND x.tipo=N'SALIDA_PALET'
            ORDER BY x.operacion_nav_id DESC
        ) n
        OUTER APPLY
        (
            SELECT TOP (1) x.etiqueta_id,x.estado
            FROM imp.etiquetas x
            WHERE x.orden_id=o.orden_id AND x.palet_id=p.palet_id
              AND x.tipo=N'PALET'
            ORDER BY x.etiqueta_id DESC
        ) e
        OUTER APPLY
        (
            SELECT TOP (1) x.trabajo_impresion_id,x.estado,x.numero_intentos
            FROM imp.trabajos_impresion x
            WHERE x.etiqueta_id=e.etiqueta_id
            ORDER BY x.trabajo_impresion_id DESC
        ) j
        ORDER BY ro.ultimo_cierre_utc DESC,o.orden_id DESC,p.numero_palet DESC,p.palet_id DESC;
        """;

    public async Task<LabelControlSnapshotRecord> ReadAsync(
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
            throw new LabelControlUnavailableException(
                "La conexion de EBIR_MES_TEST no esta configurada.");

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new SqlCommand(Query, connection)
            {
                CommandType = CommandType.Text,
                CommandTimeout = 10
            };
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            var orders = new List<OrderBuilder>();
            OrderBuilder? current = null;
            while (await reader.ReadAsync(cancellationToken))
            {
                var orderId = reader.GetInt64(0);
                if (current is null || current.OrderId != orderId)
                {
                    current = new(
                        orderId, reader.GetString(1), reader.GetString(2),
                        reader.GetString(3), reader.GetString(4), reader.GetInt64(5),
                        reader.GetString(6), reader.GetString(7), reader.GetDateTime(8));
                    orders.Add(current);
                }

                current.Pallets.Add(new(
                    reader.GetInt64(9), reader.GetInt32(10), reader.GetInt32(11),
                    reader.GetBoolean(12), reader.GetDateTime(13),
                    NullableInt64(reader, 14), NullableString(reader, 15),
                    NullableInt64(reader, 16), NullableString(reader, 17),
                    NullableInt64(reader, 18), NullableString(reader, 19),
                    reader.GetInt32(20), reader.GetBoolean(21), reader.GetBoolean(22)));
            }

            return new(DateTime.UtcNow, orders.Select(order => order.ToRecord()).ToArray());
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception exception) when (
            exception is SqlException or InvalidOperationException or FormatException)
        {
            throw new LabelControlUnavailableException(
                "No se puede consultar el control de etiquetas.", exception);
        }
    }

    private static long? NullableInt64(SqlDataReader reader, int ordinal) =>
        reader.IsDBNull(ordinal) ? null : reader.GetInt64(ordinal);

    private static string? NullableString(SqlDataReader reader, int ordinal) =>
        reader.IsDBNull(ordinal) ? null : reader.GetString(ordinal);

    private sealed class OrderBuilder(
        long orderId,
        string orderNumber,
        string productNumber,
        string productDescription,
        string orderState,
        long lineId,
        string lineCode,
        string lineName,
        DateTime lastPalletClosedAtUtc)
    {
        public long OrderId { get; } = orderId;
        public List<LabelControlPalletRecord> Pallets { get; } = [];

        public LabelControlOrderRecord ToRecord() => new(
            OrderId, orderNumber, productNumber, productDescription, orderState,
            lineId, lineCode, lineName, lastPalletClosedAtUtc, Pallets.ToArray());
    }
}
