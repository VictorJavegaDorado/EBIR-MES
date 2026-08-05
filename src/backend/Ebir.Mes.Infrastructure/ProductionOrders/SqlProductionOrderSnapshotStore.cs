using System.Data;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Ebir.Mes.Application.ProductionOrders;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.ProductionOrders;

public sealed class SqlProductionOrderSnapshotStore(string? connectionString)
    : IProductionOrderSnapshotStore
{
    private static readonly JsonSerializerOptions SerializerOptions = CreateOptions();

    public async Task<ProductionOrderSynchronizationResult> SaveAsync(
        ProductionOrderSnapshot snapshot,
        Guid synchronizationId,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            throw new ProductionOrderSynchronizationUnavailableException(
                "La conexión de EBIR_MES_TEST no está configurada.");
        }

        var json = SerializeSnapshot(snapshot);
        var hash = ComputeHash(json);

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            await using var transaction =
                (SqlTransaction)await connection.BeginTransactionAsync(cancellationToken);
            await using var command = new SqlCommand(
                "nav.aplicar_snapshot_orden",
                connection,
                transaction)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 30
            };
            command.Parameters.Add(
                "@sincronizacion_id",
                SqlDbType.UniqueIdentifier).Value = synchronizationId;
            command.Parameters.Add(
                "@snapshot_json",
                SqlDbType.NVarChar,
                -1).Value = json;
            command.Parameters.Add(
                "@snapshot_hash",
                SqlDbType.VarBinary,
                32).Value = hash;
            var inboundOrderId = command.Parameters.Add(
                "@orden_entrada_id",
                SqlDbType.BigInt);
            inboundOrderId.Direction = ParameterDirection.Output;
            var outcome = command.Parameters.Add(
                "@resultado",
                SqlDbType.NVarChar,
                20);
            outcome.Direction = ParameterDirection.Output;

            await command.ExecuteNonQueryAsync(cancellationToken);
            if (inboundOrderId.Value is null or DBNull ||
                outcome.Value is null or DBNull)
            {
                throw new ProductionOrderSynchronizationUnavailableException(
                    "La sincronización no devolvió un resultado completo.");
            }

            await using var lotCommand = new SqlCommand(
                "nav.registrar_lote_snapshot_orden",
                connection,
                transaction)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 30
            };
            lotCommand.Parameters.Add("@orden_entrada_id", SqlDbType.BigInt).Value =
                Convert.ToInt64(inboundOrderId.Value);
            lotCommand.Parameters.Add("@snapshot_hash", SqlDbType.VarBinary, 32).Value = hash;
            lotCommand.Parameters.Add("@lote", SqlDbType.NVarChar, 50).Value = snapshot.LotNumber;
            await lotCommand.ExecuteNonQueryAsync(cancellationToken);

            await using var palletFormatCommand = new SqlCommand(
                "nav.registrar_formato_palet_snapshot_orden",
                connection,
                transaction)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 30
            };
            palletFormatCommand.Parameters.Add(
                "@orden_entrada_id",
                SqlDbType.BigInt).Value = Convert.ToInt64(inboundOrderId.Value);
            palletFormatCommand.Parameters.Add(
                "@snapshot_hash",
                SqlDbType.VarBinary,
                32).Value = hash;
            palletFormatCommand.Parameters.Add(
                "@producto_codigo",
                SqlDbType.NVarChar,
                50).Value = snapshot.PalletFormat.ProductNumber;
            palletFormatCommand.Parameters.Add(
                "@codigo_formato",
                SqlDbType.NVarChar,
                50).Value = snapshot.PalletFormat.Code;
            palletFormatCommand.Parameters.Add(
                "@unidades_por_palet",
                SqlDbType.Int).Value = decimal.ToInt32(
                    snapshot.PalletFormat.QuantityPerUnitMeasure);
            await palletFormatCommand.ExecuteNonQueryAsync(cancellationToken);

            await using var postingGroupCommand = new SqlCommand(
                "nav.registrar_grupo_contable_producto_snapshot_orden",
                connection,
                transaction)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 30
            };
            postingGroupCommand.Parameters.Add(
                "@orden_entrada_id",
                SqlDbType.BigInt).Value = Convert.ToInt64(inboundOrderId.Value);
            postingGroupCommand.Parameters.Add(
                "@snapshot_hash",
                SqlDbType.VarBinary,
                32).Value = hash;
            postingGroupCommand.Parameters.Add(
                "@producto_codigo",
                SqlDbType.NVarChar,
                50).Value = snapshot.ProductPostingGroup.ProductNumber;
            postingGroupCommand.Parameters.Add(
                "@grupo_contable_producto",
                SqlDbType.NVarChar,
                50).Value = snapshot.ProductPostingGroup.Code;
            await postingGroupCommand.ExecuteNonQueryAsync(cancellationToken);
            await transaction.CommitAsync(cancellationToken);

            return new ProductionOrderSynchronizationResult(
                Convert.ToInt64(inboundOrderId.Value),
                ParseOutcome(Convert.ToString(outcome.Value)));
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (SqlException exception)
            when (TryTranslate(exception.Number, out var rejection))
        {
            if (rejection.Unavailable)
            {
                throw new ProductionOrderSynchronizationUnavailableException(
                    rejection.Message,
                    exception);
            }

            throw new ProductionOrderSynchronizationRejectedException(
                rejection.Code,
                rejection.Message,
                exception);
        }
        catch (SqlException exception)
        {
            throw new ProductionOrderSynchronizationUnavailableException(
                "No se ha podido persistir la sincronización de NAV.",
                exception);
        }
        catch (Exception exception)
            when (exception is ArgumentException or InvalidOperationException)
        {
            throw new ProductionOrderSynchronizationUnavailableException(
                "La persistencia de EBIR_MES_TEST no tiene una configuración válida.",
                exception);
        }
    }

    internal static string SerializeSnapshot(ProductionOrderSnapshot snapshot) =>
        JsonSerializer.Serialize(snapshot, SerializerOptions);

    internal static byte[] ComputeHash(string snapshotJson) =>
        SHA256.HashData(Encoding.UTF8.GetBytes(snapshotJson));

    internal static bool TryTranslate(
        int number,
        out (string Code, string Message, bool Unavailable) rejection)
    {
        rejection = number switch
        {
            55500 => ("NAV_SYNCHRONIZATION_ID_REQUIRED",
                "La correlación de sincronización es obligatoria.", false),
            55501 => ("NAV_SNAPSHOT_HASH_INVALID",
                "El snapshot NAV no es válido.", true),
            55502 => ("NAV_SNAPSHOT_INVALID",
                "El snapshot NAV no es válido.", true),
            55503 => ("NAV_SYNCHRONIZATION_ID_PARAMETER_MISMATCH",
                "La correlación ya se utilizó con otro snapshot.", false),
            55504 => ("NAV_SYNCHRONIZATION_LOCK_UNAVAILABLE",
                "La sincronización NAV no está disponible.", true),
            55505 => ("NAV_ENVIRONMENT_OR_COMPANY_NOT_AVAILABLE",
                "El entorno o la empresa NAV no están disponibles en MES.", false),
            55506 => ("NAV_SNAPSHOT_INCONSISTENT",
                "El snapshot NAV contiene datos incoherentes.", false),
            55507 => ("NAV_SINGLE_LINE_ORDER_REQUIRED",
                "El piloto requiere exactamente una línea por orden NAV.", false),
            55700 => ("NAV_INBOUND_ORDER_INVALID",
                "La orden de entrada no es válida.", false),
            55701 => ("NAV_PRODUCTION_ORDER_LOT_INVALID",
                "El lote de salida NAV no es válido.", false),
            55702 => ("NAV_SNAPSHOT_LOT_MISMATCH",
                "El lote no corresponde al snapshot NAV persistido.", false),
            55800 => ("NAV_INBOUND_ORDER_INVALID",
                "La orden de entrada no es vÃ¡lida.", false),
            55801 => ("NAV_PALLET_FORMAT_PRODUCT_INVALID",
                "El producto del formato POK no es vÃ¡lido.", false),
            55802 => ("NAV_PALLET_FORMAT_CODE_INVALID",
                "El formato de palet NAV debe ser POK.", false),
            55803 => ("NAV_PALLET_FORMAT_QUANTITY_INVALID",
                "La cantidad por palet POK debe ser un entero positivo.", false),
            55804 => ("NAV_SNAPSHOT_PALLET_FORMAT_MISMATCH",
                "El formato POK no corresponde al snapshot NAV persistido.", false),
            55900 => ("NAV_INBOUND_ORDER_INVALID",
                "La orden de entrada no es válida.", false),
            55901 => ("NAV_PRODUCT_POSTING_GROUP_PRODUCT_INVALID",
                "El producto del grupo contable no es válido.", false),
            55902 => ("NAV_PRODUCT_POSTING_GROUP_INVALID",
                "El grupo contable de producto NAV no es válido.", false),
            55903 => ("NAV_SNAPSHOT_PRODUCT_POSTING_GROUP_MISMATCH",
                "El grupo contable no corresponde al snapshot NAV persistido.", false),
            _ => default
        };
        return rejection != default;
    }

    private static ProductionOrderSynchronizationOutcome ParseOutcome(
        string? outcome) =>
        outcome switch
        {
            "CREADA" => ProductionOrderSynchronizationOutcome.Created,
            "ACTUALIZADA" => ProductionOrderSynchronizationOutcome.Updated,
            "SIN_CAMBIOS" => ProductionOrderSynchronizationOutcome.Unchanged,
            _ => throw new ProductionOrderSynchronizationUnavailableException(
                "La sincronización devolvió un resultado desconocido.")
        };

    private static JsonSerializerOptions CreateOptions()
    {
        var options = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            WriteIndented = false
        };
        options.Converters.Add(new JsonStringEnumConverter());
        return options;
    }
}
