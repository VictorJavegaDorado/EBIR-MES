using System.Data;
using Ebir.Mes.Application.ProductionOrders;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.ProductionOrders;

public sealed class SqlProductionOrderPromotionStore(string? connectionString)
    : IProductionOrderPromotionStore
{
    public async Task<ProductionOrderPromotionResult> PromoteAsync(
        ProductionOrderPromotionCommand request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
            throw new ProductionOrderPromotionUnavailableException(
                "La conexión de EBIR_MES_TEST no está configurada.");
        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new SqlCommand(
                "nav.promover_orden_entrada_con_lote_nav",
                connection)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 30
            };
            command.Parameters.Add("@promocion_id", SqlDbType.UniqueIdentifier).Value = request.CorrelationId;
            command.Parameters.Add("@orden_entrada_id", SqlDbType.BigInt).Value = request.InboundOrderId;
            command.Parameters.Add("@operacion_codigo", SqlDbType.NVarChar, 30).Value = request.OperationNumber;
            var orderId = command.Parameters.Add("@orden_id", SqlDbType.BigInt);
            orderId.Direction = ParameterDirection.Output;
            var outcome = command.Parameters.Add("@resultado", SqlDbType.NVarChar, 20);
            outcome.Direction = ParameterDirection.Output;
            await command.ExecuteNonQueryAsync(cancellationToken);
            if (orderId.Value is null or DBNull || outcome.Value is null or DBNull)
                throw new ProductionOrderPromotionUnavailableException(
                    "La promoción no devolvió un resultado completo.");
            return new(Convert.ToInt64(orderId.Value), ParseOutcome(Convert.ToString(outcome.Value)));
        }
        catch (OperationCanceledException) { throw; }
        catch (SqlException exception) when (TryTranslate(exception.Number, out var rejection))
        {
            if (rejection.Unavailable)
                throw new ProductionOrderPromotionUnavailableException(rejection.Message, exception);
            throw new ProductionOrderPromotionRejectedException(rejection.Code, rejection.Message, exception);
        }
        catch (SqlException exception)
        {
            throw new ProductionOrderPromotionUnavailableException(
                "No se ha podido promover la orden NAV.", exception);
        }
        catch (Exception exception) when (exception is ArgumentException or InvalidOperationException)
        {
            throw new ProductionOrderPromotionUnavailableException(
                "La persistencia de EBIR_MES_TEST no tiene una configuración válida.", exception);
        }
    }

    internal static bool TryTranslate(int number, out (string Code, string Message, bool Unavailable) rejection)
    {
        rejection = number switch
        {
            55600 => ("NAV_PROMOTION_ID_REQUIRED", "La correlación de promoción es obligatoria.", false),
            55601 => ("NAV_INBOUND_ORDER_INVALID", "La orden de entrada no es válida.", false),
            55602 => ("NAV_PROMOTION_LOT_INVALID", "La orden de entrada no contiene un lote NAV válido.", false),
            55603 => ("NAV_PROMOTION_OPERATION_INVALID", "La operación productiva es obligatoria.", false),
            55604 => ("NAV_PROMOTION_LOT_PROVIDER_INVALID", "El origen del lote NAV no es válido.", false),
            55605 => ("NAV_INBOUND_ORDER_NOT_FOUND", "La orden de entrada no existe.", false),
            55606 => ("NAV_INBOUND_ORDER_NOT_RELEASED", "La orden NAV no está lanzada.", false),
            55607 => ("NAV_SINGLE_LINE_ORDER_REQUIRED", "El piloto requiere exactamente una línea NAV.", false),
            55608 => ("NAV_PRODUCTION_QUANTITY_INVALID", "La cantidad NAV no es un entero productivo válido.", false),
            55609 => ("NAV_PROMOTION_OPERATION_NOT_UNIQUE", "La operación productiva no existe de forma única.", false),
            55610 => ("NAV_RUN_TIME_INVALID", "El tiempo NAV no es válido para promoción.", false),
            55611 => ("NAV_PROMOTION_LOCK_UNAVAILABLE", "La promoción no está disponible.", true),
            55612 => ("NAV_PROMOTION_ID_PARAMETER_MISMATCH", "La correlación ya se utilizó con otros parámetros.", false),
            55613 => ("NAV_PROMOTION_COMPONENTS_NOT_UNIQUE", "La orden contiene componentes repetidos no promocionables.", false),
            55614 => ("NAV_PROMOTION_PALLET_FORMAT_NOT_UNIQUE", "La orden debe contener exactamente un formato POK.", false),
            55615 => ("NAV_PROMOTION_PALLET_FORMAT_INVALID", "El formato POK no corresponde al producto o cantidad de la orden.", false),
            55616 => ("NAV_PROMOTION_PALLET_FORMAT_CONFLICT", "La orden productiva ya contiene otro formato POK.", false),
            55617 => ("NAV_PROMOTION_PRODUCT_POSTING_GROUP_NOT_UNIQUE", "La orden debe contener un único grupo contable de producto.", false),
            55618 => ("NAV_PROMOTION_PRODUCT_POSTING_GROUP_INVALID", "El grupo contable no corresponde al producto de la orden.", false),
            55619 => ("NAV_PROMOTION_PRODUCT_POSTING_GROUP_CONFLICT", "La orden productiva ya contiene otro grupo contable.", false),
            _ => default
        };
        return rejection != default;
    }

    private static ProductionOrderPromotionOutcome ParseOutcome(string? outcome) => outcome switch
    {
        "CREADA" => ProductionOrderPromotionOutcome.Created,
        "SIN_CAMBIOS" => ProductionOrderPromotionOutcome.Unchanged,
        "REVISION" => ProductionOrderPromotionOutcome.ReviewRequired,
        _ => throw new ProductionOrderPromotionUnavailableException(
            "La promoción devolvió un resultado desconocido.")
    };
}
