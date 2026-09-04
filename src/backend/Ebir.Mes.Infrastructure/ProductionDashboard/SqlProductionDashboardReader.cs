using System.Data;
using Ebir.Mes.Application.ProductionDashboard;
using Ebir.Mes.Application.ProductionOrders;
using Ebir.Mes.Application.ProductionWorkstations;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.ProductionDashboard;

public sealed class SqlProductionDashboardReader(string? connectionString)
    : IProductionDashboardReader
{
    private const string LinesQuery = """
        DECLARE @ahora_utc datetime2(3)=SYSUTCDATETIME();

        SELECT
            l.linea_id, l.codigo, l.nombre,
            c.codigo AS centro_codigo, c.nombre AS centro_nombre,
            COALESCE(el.estado,N'LIBRE') AS estado_operativo,
            el.motivo_bloqueo, el.actualizado_utc,
            s.sesion_linea_id,
            o.orden_id, o.numero_orden, o.producto_codigo,
            o.producto_descripcion, o.lote, o.cantidad_objetivo,
            o.cantidad_buena_acumulada, o.cantidad_reservada_activa,
            o.cantidad_scrap_acumulada, o.tiempo_ejecucion_nav_min,
            o.estado AS estado_orden, o.importada_utc,
            COALESCE(metricas.palets_cerrados,0) AS palets_cerrados,
            ultimo_nav.estado AS ultimo_estado_nav,
            ultima_etiqueta.estado AS ultimo_estado_etiqueta,
            COALESCE(metricas.nav_pendientes,0) AS nav_pendientes,
            COALESCE(metricas.nav_incidencias,0) AS nav_incidencias,
            COALESCE(metricas.impresiones_pendientes,0) AS impresiones_pendientes,
            COALESCE(metricas.impresiones_incidencia,0) AS impresiones_incidencia,
            COALESCE(metricas.unidades_teoricas_acumuladas,0) AS unidades_teoricas_acumuladas
        FROM cfg.lineas l
        INNER JOIN cfg.centros_trabajo c
            ON c.centro_trabajo_id=l.centro_trabajo_id
        LEFT JOIN prod.estados_linea el ON el.linea_id=l.linea_id
        LEFT JOIN prod.sesiones_linea s
            ON s.sesion_linea_id=el.sesion_linea_id
           AND s.finalizada_utc IS NULL
        LEFT JOIN prod.ordenes o ON o.orden_id=s.orden_id
        OUTER APPLY
        (
            SELECT
                (SELECT COUNT(*) FROM prod.palets p
                 WHERE p.orden_id=o.orden_id AND p.estado=N'CERRADO') AS palets_cerrados,
                (SELECT COUNT(*) FROM nav.operaciones n
                 WHERE n.orden_id=o.orden_id AND n.tipo=N'SALIDA_PALET'
                   AND n.estado IN (N'PENDIENTE',N'PROCESANDO',N'ERROR_REINTENTABLE',N'RESULTADO_DESCONOCIDO')) AS nav_pendientes,
                (SELECT COUNT(*) FROM nav.operaciones n
                 WHERE n.orden_id=o.orden_id AND n.tipo=N'SALIDA_PALET'
                   AND n.estado=N'ERROR_DEFINITIVO') AS nav_incidencias,
                (SELECT COUNT(*) FROM imp.trabajos_impresion ti
                 JOIN imp.etiquetas e ON e.etiqueta_id=ti.etiqueta_id
                 WHERE e.orden_id=o.orden_id AND ti.es_reimpresion=0
                   AND ti.estado IN (N'PENDIENTE',N'PROCESANDO')) AS impresiones_pendientes,
                (SELECT COUNT(*) FROM imp.trabajos_impresion ti
                 JOIN imp.etiquetas e ON e.etiqueta_id=ti.etiqueta_id
                 WHERE e.orden_id=o.orden_id AND ti.es_reimpresion=0
                   AND ti.estado=N'ERROR') AS impresiones_incidencia,
                (SELECT SUM(
                    CONVERT(decimal(38,10),tc.capacidad_teorica_hora)
                    * CONVERT(decimal(38,10),DATEDIFF_BIG(
                        MILLISECOND,tc.inicio_utc,COALESCE(tc.fin_utc,@ahora_utc)))
                    / CONVERT(decimal(38,10),3600000))
                 FROM prod.tramos_capacidad tc
                 WHERE tc.sesion_linea_id=s.sesion_linea_id) AS unidades_teoricas_acumuladas
        ) metricas
        OUTER APPLY
        (
            SELECT TOP (1) n.estado
            FROM nav.operaciones n
            WHERE n.orden_id=o.orden_id AND n.tipo=N'SALIDA_PALET'
            ORDER BY n.operacion_nav_id DESC
        ) ultimo_nav
        OUTER APPLY
        (
            SELECT TOP (1) e.estado
            FROM imp.etiquetas e
            WHERE e.orden_id=o.orden_id AND e.tipo=N'PALET'
            ORDER BY e.etiqueta_id DESC
        ) ultima_etiqueta
        WHERE l.activa=1 AND c.activo=1
        ORDER BY c.codigo,l.codigo,l.linea_id;
        """;

    public async Task<ProductionDashboardSnapshotRecord> ReadAsync(
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            throw new ProductionDashboardUnavailableException(
                "La conexion de EBIR_MES_TEST no esta configurada.");
        }

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            var lines = await ReadLinesAsync(connection, cancellationToken);

            foreach (var line in lines.Where(line => line.SessionId.HasValue))
            {
                line.Table = await ReadTableAsync(
                    connection,
                    line.Order!.ProductionOrderId,
                    line.LineId,
                    cancellationToken);
                if (line.Table is null || line.Table.LineSessionId != line.SessionId)
                {
                    throw new ProductionDashboardUnavailableException(
                        "El estado agregado de una linea activa no es coherente.");
                }
            }

            return new ProductionDashboardSnapshotRecord(
                DateTime.UtcNow,
                lines.Select(line => line.ToRecord()).ToArray());
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (ProductionDashboardUnavailableException)
        {
            throw;
        }
        catch (SqlException exception)
        {
            throw new ProductionDashboardUnavailableException(
                "No se ha podido leer el panel de fabricacion.", exception);
        }
        catch (Exception exception)
            when (exception is ArgumentException or InvalidOperationException)
        {
            throw new ProductionDashboardUnavailableException(
                "La conexion de EBIR_MES_TEST no tiene una configuracion valida.",
                exception);
        }
    }

    private static async Task<List<DashboardLineBuilder>> ReadLinesAsync(
        SqlConnection connection,
        CancellationToken cancellationToken)
    {
        await using var command = new SqlCommand(LinesQuery, connection)
        {
            CommandType = CommandType.Text,
            CommandTimeout = 10
        };
        await using var reader = await command.ExecuteReaderAsync(
            CommandBehavior.SingleResult,
            cancellationToken);
        var lines = new List<DashboardLineBuilder>();
        while (await reader.ReadAsync(cancellationToken))
        {
            var sessionId = reader.IsDBNull(8) ? (long?)null : reader.GetInt64(8);
            ProductionOrderSelectionRecord? order = null;
            if (sessionId.HasValue)
            {
                if (reader.IsDBNull(9))
                {
                    throw new ProductionDashboardUnavailableException(
                        "Una sesion activa no tiene orden asociada.");
                }
                order = new ProductionOrderSelectionRecord(
                    reader.GetInt64(9), reader.GetString(10), reader.GetString(11),
                    reader.GetString(12), reader.GetString(13), reader.GetInt32(14),
                    reader.GetInt32(15), reader.GetInt32(16), reader.GetInt32(17),
                    reader.GetDecimal(18), reader.GetString(19),
                    AsUtc(reader.GetDateTime(20)));
            }

            lines.Add(new DashboardLineBuilder(
                reader.GetInt64(0), reader.GetString(1), reader.GetString(2),
                reader.GetString(3), reader.GetString(4), reader.GetString(5),
                reader.IsDBNull(6) ? null : reader.GetString(6),
                reader.IsDBNull(7) ? null : AsUtc(reader.GetDateTime(7)),
                sessionId, order,
                reader.GetInt32(21),
                reader.IsDBNull(22) ? null : reader.GetString(22),
                reader.IsDBNull(23) ? null : reader.GetString(23),
                reader.GetInt32(24), reader.GetInt32(25),
                reader.GetInt32(26), reader.GetInt32(27), reader.GetDecimal(28)));
        }
        return lines;
    }

    private static async Task<ProductionTableStateRecord?> ReadTableAsync(
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
        if (!await reader.ReadAsync(cancellationToken)) return null;

        var sessionId = reader.GetInt64(0);
        var stateOrderId = reader.GetInt64(1);
        var stateLineId = reader.GetInt64(2);
        var state = reader.GetString(3);
        var startedAt = reader.IsDBNull(4) ? (DateTime?)null : AsUtc(reader.GetDateTime(4));
        var serverTime = AsUtc(reader.GetDateTime(5));
        var productiveSeconds = reader.GetInt64(6);
        var activeResources = reader.GetInt32(7);
        var capacity = reader.GetDecimal(8);
        var format = reader.GetString(9);
        var unitsPerPallet = reader.GetInt32(10);
        var operators = new List<ProductionTableOperatorRecord>();
        if (await reader.NextResultAsync(cancellationToken))
        {
            while (await reader.ReadAsync(cancellationToken))
            {
                operators.Add(new ProductionTableOperatorRecord(
                    reader.GetInt64(0), reader.GetString(1), reader.GetString(2),
                    AsUtc(reader.GetDateTime(3)), reader.GetInt64(4),
                    reader.GetString(5)));
            }
        }
        return new ProductionTableStateRecord(
            sessionId, stateOrderId, stateLineId, state, startedAt, serverTime,
            productiveSeconds, activeResources, capacity, format, unitsPerPallet,
            operators);
    }

    private static DateTime AsUtc(DateTime value) =>
        DateTime.SpecifyKind(value, DateTimeKind.Utc);

    private sealed record DashboardLineBuilder(
        long LineId,
        string LineCode,
        string LineName,
        string WorkCenterCode,
        string WorkCenterName,
        string OperationalState,
        string? BlockReason,
        DateTime? UpdatedAtUtc,
        long? SessionId,
        ProductionOrderSelectionRecord? Order,
        int ClosedPallets,
        string? LatestNavState,
        string? LatestLabelState,
        int PendingNavOutputs,
        int NavIssues,
        int PendingPrintJobs,
        int PrintIssues,
        decimal TheoreticalUnitsToDate)
    {
        public ProductionTableStateRecord? Table { get; set; }

        public ProductionDashboardLineRecord ToRecord() => new(
            LineId, LineCode, LineName, WorkCenterCode, WorkCenterName,
            OperationalState, BlockReason, UpdatedAtUtc, Order, Table,
            ClosedPallets, LatestNavState, LatestLabelState, PendingNavOutputs,
            NavIssues, PendingPrintJobs, PrintIssues, TheoreticalUnitsToDate);
    }
}
