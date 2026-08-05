using System.Data;
using Ebir.Mes.Application.Pallets.ClosePalletOptions;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.Pallets;

public sealed class SqlPalletCloseOptionsReader(string? connectionString)
    : IPalletCloseOptionsReader
{
    private const string Query = """
        SELECT
            r.reserva_palet_id,
            r.cantidad_reservada,
            o.numero_orden,
            o.producto_codigo,
            o.producto_descripcion,
            o.grupo_contable_producto,
            l.nombre
        FROM prod.reservas_palet AS r
        INNER JOIN prod.sesiones_linea AS s
            ON s.sesion_linea_id = r.sesion_linea_id
        INNER JOIN prod.ordenes AS o
            ON o.orden_id = r.orden_id
        INNER JOIN cfg.lineas AS l
            ON l.linea_id = s.linea_id
        INNER JOIN prod.estados_linea AS el
            ON el.linea_id = s.linea_id
           AND el.sesion_linea_id = s.sesion_linea_id
        WHERE s.linea_id = @linea_id
          AND r.estado = N'ACTIVA'
          AND NULLIF(LTRIM(RTRIM(o.grupo_contable_producto)), N'') IS NOT NULL
        ORDER BY r.creada_utc, r.reserva_palet_id;

        SELECT DISTINCT
            e.empleado_id,
            e.codigo_nav,
            e.nombre_completo
        FROM seg.empleados AS e
        INNER JOIN prod.fichajes AS f
            ON f.empleado_id = e.empleado_id
           AND f.salida_utc IS NULL
        INNER JOIN prod.sesiones_linea AS s
            ON s.sesion_linea_id = f.sesion_linea_id
           AND s.linea_id = @linea_id
           AND s.finalizada_utc IS NULL
        INNER JOIN prod.estados_linea AS el
            ON el.linea_id = s.linea_id
           AND el.sesion_linea_id = s.sesion_linea_id
        INNER JOIN seg.empleados_roles AS er
            ON er.empleado_id = e.empleado_id
        INNER JOIN seg.roles AS rol
            ON rol.rol_id = er.rol_id
        WHERE e.activo_mes = 1
          AND e.anonimizado_utc IS NULL
          AND rol.activo = 1
          AND rol.codigo IN (N'OPERARIO', N'SUPERVISOR')
          AND er.desde_utc <= SYSUTCDATETIME()
          AND (er.hasta_utc IS NULL OR er.hasta_utc >= SYSUTCDATETIME())
          AND NOT EXISTS
          (
              SELECT 1
              FROM prod.paros_operario AS po
              WHERE po.fichaje_id = f.fichaje_id
                AND po.fin_utc IS NULL
          )
        ORDER BY e.nombre_completo, e.empleado_id;

        SELECT DISTINCT
            e.empleado_id,
            e.codigo_nav,
            e.nombre_completo
        FROM seg.empleados AS e
        INNER JOIN seg.empleados_roles AS er
            ON er.empleado_id = e.empleado_id
        INNER JOIN seg.roles AS rol
            ON rol.rol_id = er.rol_id
        WHERE e.activo_mes = 1
          AND e.anonimizado_utc IS NULL
          AND rol.activo = 1
          AND rol.codigo = N'SUPERVISOR'
          AND er.desde_utc <= SYSUTCDATETIME()
          AND (er.hasta_utc IS NULL OR er.hasta_utc >= SYSUTCDATETIME())
        ORDER BY e.nombre_completo, e.empleado_id;
        """;

    public async Task<PalletCloseOptionsRecord> ReadAsync(
        long lineId,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            throw new PalletCloseOptionsUnavailableException(
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
            command.Parameters.Add("@linea_id", SqlDbType.BigInt).Value = lineId;

            var reservations = new List<PalletReservationOption>();
            var employees = new List<PalletEmployeeOption>();
            var supervisors = new List<PalletEmployeeOption>();
            await using var reader = await command.ExecuteReaderAsync(
                CommandBehavior.Default,
                cancellationToken);

            while (await reader.ReadAsync(cancellationToken))
            {
                reservations.Add(new(
                    reader.GetInt64(0),
                    reader.GetInt32(1),
                    reader.GetString(2),
                    reader.GetString(3),
                    reader.GetString(4),
                    reader.GetString(5),
                    reader.GetString(6)));
            }

            await reader.NextResultAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                employees.Add(ReadEmployee(reader));
            }

            await reader.NextResultAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                supervisors.Add(ReadEmployee(reader));
            }

            return new(reservations, employees, supervisors);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (SqlException exception)
        {
            throw new PalletCloseOptionsUnavailableException(
                "No se han podido consultar las opciones de cierre.",
                exception);
        }
        catch (Exception exception)
            when (exception is ArgumentException or InvalidOperationException)
        {
            throw new PalletCloseOptionsUnavailableException(
                "La conexión de EBIR_MES_TEST no tiene una configuración válida.",
                exception);
        }
    }

    private static PalletEmployeeOption ReadEmployee(SqlDataReader reader) =>
        new(reader.GetInt64(0), reader.GetString(1), reader.GetString(2));
}
