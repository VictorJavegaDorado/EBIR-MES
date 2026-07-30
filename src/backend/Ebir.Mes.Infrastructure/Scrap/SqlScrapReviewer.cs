using System.Data;
using Ebir.Mes.Application.Scrap;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.Scrap;

public sealed class SqlScrapReviewer(string? connectionString) : IScrapReviewer
{
    public async Task<ReviewedScrapRecord> ReviewAsync(
        ReviewScrapCommand request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
            throw new ScrapUnavailableException(
                "La conexión de EBIR_MES_TEST no está configurada.");
        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new SqlCommand("[log].revisar_scrap", connection)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 10
            };
            command.Parameters.Add("@scrap_id", SqlDbType.BigInt).Value =
                request.ScrapId;
            command.Parameters.Add("@componente_orden_id", SqlDbType.BigInt).Value =
                request.OrderComponentId;
            command.Parameters.Add("@motivo_scrap_id", SqlDbType.SmallInt).Value =
                request.ScrapReasonId;
            command.Parameters.Add("@cantidad", SqlDbType.Int).Value = request.Quantity;
            command.Parameters.Add(
                "@descripcion",
                SqlDbType.NVarChar,
                ReviewScrap.MaximumDescriptionLength).Value =
                request.Description is null ? DBNull.Value : request.Description;
            command.Parameters.Add("@es_anulacion", SqlDbType.Bit).Value =
                request.IsCancellation;
            command.Parameters.Add("@ajustado_por_supervisor_id", SqlDbType.BigInt).Value =
                request.AdjustedBySupervisorId;
            command.Parameters.Add(
                "@motivo_ajuste",
                SqlDbType.NVarChar,
                ReviewScrap.MaximumAdjustmentReasonLength).Value =
                request.AdjustmentReason;
            command.Parameters.Add("@correlacion_id", SqlDbType.UniqueIdentifier).Value =
                request.CorrelationId;
            var revisionId =
                command.Parameters.Add("@revision_scrap_id", SqlDbType.BigInt);
            revisionId.Direction = ParameterDirection.Output;
            var navOperationId =
                command.Parameters.Add("@operacion_nav_id", SqlDbType.BigInt);
            navOperationId.Direction = ParameterDirection.Output;
            await command.ExecuteNonQueryAsync(cancellationToken);
            return new(
                Convert.ToInt64(revisionId.Value),
                Convert.ToInt64(navOperationId.Value));
        }
        catch (OperationCanceledException) { throw; }
        catch (SqlException exception)
            when (TryTranslate(exception.Number, out var rejection))
        {
            throw new ScrapRejectedException(
                rejection.Code, rejection.Message, exception);
        }
        catch (SqlException exception)
        {
            throw new ScrapUnavailableException(
                "No se ha podido revisar el scrap.", exception);
        }
        catch (Exception exception)
            when (exception is ArgumentException or InvalidOperationException)
        {
            throw new ScrapUnavailableException(
                "La conexión de EBIR_MES_TEST no tiene una configuración válida.",
                exception);
        }
    }

    internal static bool TryTranslate(
        int number,
        out (string Code, string Message) rejection)
    {
        rejection = number switch
        {
            55100 => ("SCRAP_ID_REQUIRED", "El scrap es obligatorio."),
            55101 => ("ORDER_COMPONENT_ID_REQUIRED", "El componente es obligatorio."),
            55102 => ("SCRAP_REASON_ID_REQUIRED", "El motivo de scrap es obligatorio."),
            55103 => ("SCRAP_REVIEW_TYPE_REQUIRED",
                "Debe indicarse el tipo de revisión."),
            55104 => ("SCRAP_REVIEW_QUANTITY_INVALID",
                "La cantidad no corresponde al tipo de revisión."),
            55105 => ("ADJUSTED_BY_SUPERVISOR_ID_REQUIRED",
                "El supervisor es obligatorio."),
            55106 => ("SCRAP_ADJUSTMENT_REASON_REQUIRED",
                "El motivo de ajuste es obligatorio."),
            55107 => ("CORRELATION_ID_REQUIRED", "La correlación es obligatoria."),
            55108 => ("SCRAP_REVIEW_IDEMPOTENCY_LOCK_UNAVAILABLE",
                "No se pudo asegurar la idempotencia de la revisión."),
            55109 => ("CORRELATION_ID_ALREADY_USED",
                "La correlación ya pertenece a otra operación."),
            55110 => ("CORRELATION_ID_PARAMETER_MISMATCH",
                "La correlación ya se utilizó con parámetros diferentes."),
            55111 => ("SCRAP_NOT_FOUND", "El scrap no existe."),
            55112 => ("SCRAP_ORDER_NOT_FOUND", "La orden asociada no existe."),
            55113 => ("SUPERVISOR_NOT_ACTIVE",
                "La revisión requiere supervisor activo."),
            55114 => ("ORDER_COMPONENT_NOT_FOUND",
                "El componente no pertenece a la orden del scrap."),
            55115 => ("SCRAP_REASON_NOT_ACTIVE",
                "El motivo de scrap no existe o no está activo."),
            55116 => ("SCRAP_DESCRIPTION_REQUIRED",
                "El motivo seleccionado requiere descripción."),
            55117 => ("SCRAP_REVIEW_HAS_NO_CHANGES",
                "La revisión no modifica el valor efectivo."),
            55118 => ("SCRAP_NAV_OPERATION_NOT_FOUND",
                "El scrap no tiene operación de consumo asociada."),
            55119 => ("SCRAP_NAV_RESULT_PENDING_OR_UNKNOWN",
                "El resultado del consumo está en curso o es incierto."),
            55120 => ("SCRAP_ACCUMULATED_QUANTITY_NEGATIVE",
                "El ajuste produciría un acumulado negativo."),
            55121 => ("PREVIOUS_SCRAP_REVIEW_INCOMPLETE",
                "La revisión anterior está incompleta."),
            55122 => ("SCRAP_TRANSACTION_LOCK_UNAVAILABLE",
                "No se pudo bloquear el scrap para su revisión."),
            _ => default
        };
        return rejection != default;
    }
}
