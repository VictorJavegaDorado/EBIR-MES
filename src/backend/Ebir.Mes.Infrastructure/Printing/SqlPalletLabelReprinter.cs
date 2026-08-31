using System.Data;
using Ebir.Mes.Application.Printing;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.Printing;

public sealed class SqlPalletLabelReprinter(string? connectionString)
    : IPalletLabelReprinter
{
    public async Task<ReprintedPalletLabelRecord> ReprintAsync(
        ReprintPalletLabelCommand request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
            throw new PalletLabelReprintUnavailableException(
                "La conexión de EBIR_MES_TEST no está configurada.");

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new SqlCommand(
                "imp.solicitar_reimpresion_palet",
                connection)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 10
            };
            command.Parameters.Add("@palet_id", SqlDbType.BigInt).Value =
                request.PalletId;
            command.Parameters.Add(
                "@solicitado_por_supervisor_id",
                SqlDbType.BigInt).Value = request.RequestedBySupervisorId;
            command.Parameters.Add(
                "@motivo",
                SqlDbType.NVarChar,
                ReprintPalletLabel.MaximumReasonLength).Value = request.Reason;
            command.Parameters.Add(
                "@correlacion_id",
                SqlDbType.UniqueIdentifier).Value = request.CorrelationId;
            var printJobId = command.Parameters.Add(
                "@trabajo_impresion_id",
                SqlDbType.BigInt);
            printJobId.Direction = ParameterDirection.Output;

            await command.ExecuteNonQueryAsync(cancellationToken);
            if (printJobId.Value is null or DBNull)
                throw new PalletLabelReprintUnavailableException(
                    "La reimpresión no devolvió un trabajo de impresión.");
            return new(Convert.ToInt64(printJobId.Value));
        }
        catch (OperationCanceledException) { throw; }
        catch (SqlException exception)
            when (TryTranslate(exception.Number, out var rejection))
        {
            throw new PalletLabelReprintRejectedException(
                rejection.Code,
                rejection.Message,
                exception);
        }
        catch (SqlException exception)
        {
            throw new PalletLabelReprintUnavailableException(
                "No se ha podido solicitar la reimpresión.",
                exception);
        }
        catch (Exception exception)
            when (exception is ArgumentException or InvalidOperationException)
        {
            throw new PalletLabelReprintUnavailableException(
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
            56500 => ("PALLET_ID_REQUIRED", "El palé es obligatorio."),
            56501 => ("REPRINT_SUPERVISOR_ID_REQUIRED",
                "La reimpresión requiere un supervisor."),
            56502 => ("REPRINT_REASON_REQUIRED",
                "El motivo de reimpresión es obligatorio."),
            56503 => ("CORRELATION_ID_REQUIRED",
                "La correlación es obligatoria."),
            56504 => ("REPRINT_IDEMPOTENCY_LOCK_UNAVAILABLE",
                "No se pudo asegurar la idempotencia de la reimpresión."),
            56505 => ("CORRELATION_ID_ALREADY_USED",
                "La correlación ya pertenece a otra operación."),
            56506 => ("CORRELATION_ID_PARAMETER_MISMATCH",
                "La correlación ya se utilizó con parámetros diferentes."),
            56507 => ("PALLET_NOT_FOUND", "El palé no existe."),
            56508 => ("REPRINT_SUPERVISOR_NOT_ACTIVE",
                "La reimpresión requiere un supervisor activo."),
            56509 => ("PALLET_LABEL_NOT_FOUND",
                "El palé no tiene una etiqueta disponible."),
            56510 => ("PALLET_LABEL_NOT_PRINTED",
                "La etiqueta original todavía no consta como impresa."),
            56511 => ("ORIGINAL_PRINT_NOT_COMPLETED",
                "No existe una impresión original completada."),
            56512 => ("PALLET_LABEL_PRINT_ALREADY_OPEN",
                "Ya existe una impresión pendiente para esta etiqueta."),
            56513 => ("PRIMARY_PRINTER_NOT_AVAILABLE",
                "La línea no tiene una impresora principal disponible."),
            _ => default
        };
        return rejection != default;
    }
}
