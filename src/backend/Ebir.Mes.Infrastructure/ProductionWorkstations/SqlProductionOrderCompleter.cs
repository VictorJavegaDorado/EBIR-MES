using System.Data;
using Ebir.Mes.Application.ProductionWorkstations;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.ProductionWorkstations;

public sealed class SqlProductionOrderCompleter(string? connectionString)
    : IProductionOrderCompleter
{
    public async Task CompleteAsync(
        CompleteProductionOrderCommand request,
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
            await using var command = new SqlCommand(
                "prod.finalizar_orden_produccion",
                connection)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 10
            };
            command.Parameters.Add("@sesion_linea_id", SqlDbType.BigInt).Value =
                request.LineSessionId;
            command.Parameters.Add("@correlacion_id", SqlDbType.UniqueIdentifier).Value =
                request.CorrelationId;

            await command.ExecuteNonQueryAsync(cancellationToken);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (SqlException exception) when (TryTranslate(exception.Number, out var rejection))
        {
            throw new ProductionTableRejectedException(
                rejection.Code,
                rejection.Message,
                exception);
        }
        catch (SqlException exception)
        {
            throw new ProductionTableUnavailableException(
                "No se ha podido finalizar la orden de producción.",
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

    internal static bool TryTranslate(
        int sqlErrorNumber,
        out (string Code, string Message) rejection)
    {
        rejection = sqlErrorNumber switch
        {
            52800 => ("CORRELATION_ID_REQUIRED", "La correlación es obligatoria."),
            52801 => ("LINE_SESSION_NOT_FOUND", "La sesión de línea no existe."),
            52802 => ("ORDER_NOT_FOUND", "La orden no existe."),
            52803 => ("ORDER_STATE_NOT_READY", "La orden todavía no admite su finalización."),
            52804 => ("LINE_SESSION_NOT_READY", "La mesa todavía no admite su finalización."),
            52805 => ("LINE_SESSION_MISMATCH", "La línea ya no corresponde a esta mesa."),
            52806 => ("LINE_STATE_NOT_READY", "La línea todavía no admite su liberación."),
            52807 => ("ORDER_QUANTITY_NOT_COMPLETE", "La cantidad productiva de la orden no está completa."),
            52808 => ("ACTIVE_PRODUCTION_RESOURCES", "Todavía existen recursos productivos activos."),
            52809 => ("ACTIVE_PALLET_RESERVATION", "Todavía existe una reserva de palé activa."),
            52810 => ("FINAL_PALLET_NOT_VALID", "El último palé no está cerrado y autorizado correctamente."),
            52811 => ("PALLET_OUTPUT_NOT_CONFIRMED", "Todas las salidas de palé deben estar confirmadas."),
            52812 => ("PALLET_LABEL_NOT_READY", "Todas las etiquetas deben estar listas o impresas."),
            52813 => ("ORDER_COMPLETION_CHANGED", "La orden cambió durante la finalización; vuelve a intentarlo."),
            _ => default
        };
        return rejection != default;
    }
}
