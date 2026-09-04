using System.Data;
using Ebir.Mes.Application.PalletRecovery;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.PalletRecovery;

public sealed class SqlPalletRecoveryStateReader(string? connectionString)
    : IPalletRecoveryStateReader
{
    private const string Query = """
        SELECT TOP (1)
            p.palet_id,
            p.numero_palet,
            n.operacion_nav_id,
            n.estado,
            COALESCE(n.numero_intentos, 0),
            CONVERT(bit, CASE WHEN
                n.estado=N'RESULTADO_DESCONOCIDO'
                AND n.numero_intentos=12
                AND n.proximo_intento_utc IS NULL
                AND NULLIF(LTRIM(RTRIM(n.identificador_externo)),N'') IS NOT NULL
                AND COALESCE(JSON_VALUE(ultimo.respuesta,N'$.reason'),N'') NOT IN
                    (N'MultipleNewOutputs',N'ReconciliationTruncated',N'ReconciliationMismatch',
                     N'ReconciliationRowNotUnique',N'ExternalIdentifierInvalid',N'BaselineMaximumIdMissing')
                THEN 1 ELSE 0 END),
            e.estado,
            CONVERT(bit, CASE WHEN e.estado=N'IMPRESA'
                AND EXISTS (SELECT 1 FROM imp.trabajos_impresion t
                    WHERE t.etiqueta_id=e.etiqueta_id AND t.es_reimpresion=0
                      AND t.estado=N'COMPLETADO')
                AND NOT EXISTS (SELECT 1 FROM imp.trabajos_impresion t
                    WHERE t.etiqueta_id=e.etiqueta_id
                      AND t.estado IN (N'PENDIENTE',N'PROCESANDO'))
                THEN 1 ELSE 0 END)
        FROM prod.palets p
        LEFT JOIN nav.operaciones n
          ON n.palet_id=p.palet_id AND n.orden_id=p.orden_id AND n.tipo=N'SALIDA_PALET'
        OUTER APPLY
        (
            SELECT TOP (1) i.respuesta
            FROM nav.intentos_operacion i
            WHERE i.operacion_nav_id=n.operacion_nav_id
            ORDER BY i.numero_intento DESC, i.intento_operacion_id DESC
        ) ultimo
        OUTER APPLY
        (
            SELECT TOP (1) x.etiqueta_id,x.estado
            FROM imp.etiquetas x
            WHERE x.palet_id=p.palet_id AND x.orden_id=p.orden_id AND x.tipo=N'PALET'
            ORDER BY x.etiqueta_id DESC
        ) e
        WHERE p.sesion_linea_id=@sesion_linea_id AND p.estado=N'CERRADO'
        ORDER BY p.numero_palet DESC,p.palet_id DESC;
        """;

    public async Task<PalletRecoveryStateRecord?> ReadLatestAsync(
        long lineSessionId,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
            throw new PalletRecoveryUnavailableException(
                "La conexion de EBIR_MES_TEST no esta configurada.");
        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new SqlCommand(Query, connection)
            {
                CommandType = CommandType.Text,
                CommandTimeout = 5
            };
            command.Parameters.Add("@sesion_linea_id", SqlDbType.BigInt).Value =
                lineSessionId;
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken)) return null;
            return new(
                reader.GetInt64(0), reader.GetInt32(1),
                reader.IsDBNull(2) ? null : reader.GetInt64(2),
                reader.IsDBNull(3) ? null : reader.GetString(3), reader.GetInt32(4),
                reader.GetBoolean(5), reader.IsDBNull(6) ? null : reader.GetString(6),
                reader.GetBoolean(7));
        }
        catch (OperationCanceledException) { throw; }
        catch (SqlException exception)
        {
            throw new PalletRecoveryUnavailableException(
                "No se puede consultar la recuperacion del ultimo pale.", exception);
        }
    }
}
