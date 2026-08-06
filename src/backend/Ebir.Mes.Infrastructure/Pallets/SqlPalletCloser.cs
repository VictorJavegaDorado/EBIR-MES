using System.Data;
using Ebir.Mes.Application.Pallets.ClosePallet;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.Pallets;

public sealed class SqlPalletCloser(string? connectionString) : IPalletCloser
{
    public async Task<ClosedPalletRecord> CloseAsync(
        ClosePalletCommand request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
            throw new PalletCloseUnavailableException("La conexión de EBIR_MES_TEST no está configurada.");
        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new SqlCommand("prod.cerrar_palet_idempotente", connection)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 30
            };
            command.Parameters.Add("@reserva_palet_id", SqlDbType.BigInt).Value = request.ReservationId;
            command.Parameters.Add("@cantidad_buena", SqlDbType.Int).Value = request.GoodQuantity;
            command.Parameters.Add("@cerrado_por_empleado_id", SqlDbType.BigInt).Value = request.ClosedByEmployeeId;
            command.Parameters.Add("@supervisor_autorizador_id", SqlDbType.BigInt).Value = request.AuthorizingSupervisorId is null ? DBNull.Value : request.AuthorizingSupervisorId.Value;
            command.Parameters.Add("@es_parcial", SqlDbType.Bit).Value = request.IsPartial;
            command.Parameters.Add("@motivo_parcial", SqlDbType.NVarChar, 30).Value = request.PartialReason is null ? DBNull.Value : request.PartialReason;
            command.Parameters.Add("@correlacion_id", SqlDbType.UniqueIdentifier).Value = request.CorrelationId;
            var palletId = command.Parameters.Add("@palet_id", SqlDbType.BigInt);
            palletId.Direction = ParameterDirection.Output;
            await command.ExecuteNonQueryAsync(cancellationToken);
            if (palletId.Value is null or DBNull)
                throw new PalletCloseUnavailableException("El cierre no devolvió un identificador de palé.");
            return new ClosedPalletRecord(Convert.ToInt64(palletId.Value));
        }
        catch (OperationCanceledException) { throw; }
        catch (SqlException exception) when (TryTranslate(exception.Number, out var rejection))
        {
            if (rejection.Unavailable) throw new PalletCloseUnavailableException(rejection.Message, exception);
            throw new PalletCloseRejectedException(rejection.Code, rejection.Message, exception);
        }
        catch (SqlException exception)
        {
            throw new PalletCloseUnavailableException("No se ha podido cerrar el palé.", exception);
        }
        catch (Exception exception) when (exception is ArgumentException or InvalidOperationException)
        {
            throw new PalletCloseUnavailableException("La conexión de EBIR_MES_TEST no tiene una configuración válida.", exception);
        }
    }

    internal static bool TryTranslate(int number, out (string Code, string Message, bool Unavailable) rejection)
    {
        rejection = number switch
        {
            51400 => ("PALLET_GOOD_QUANTITY_INVALID", "La cantidad buena no es válida.", false),
            51401 => ("PALLET_CLOSER_ROLE_NOT_ALLOWED", "El empleado no puede cerrar el palé.", false),
            51402 => ("PALLET_PARTIAL_REASON_INVALID", "El motivo de cierre parcial no es válido.", false),
            51403 => ("ACTIVE_PALLET_RESERVATION_NOT_FOUND", "La reserva activa no está disponible.", false),
            51404 => ("PALLET_GOOD_QUANTITY_EXCEEDS_RESERVATION", "La cantidad supera la reserva.", false),
            51405 => ("PALLET_PARTIAL_CLOSE_REQUIRED", "El cierre debe ser parcial.", false),
            51406 => ("PALLET_CLOSE_EXCEEDS_GOOD_TARGET", "El cierre supera el objetivo bueno.", false),
            51407 => ("PALLET_CLOSE_SUPERVISOR_REQUIRED", "El cierre requiere supervisor.", false),
            51408 => ("LINE_STATE_NOT_ALLOWED_FOR_PALLET_CLOSE", "La línea no admite el cierre.", false),
            51409 => ("OTHER_ACTIVE_PALLET_RESERVATIONS_EXIST", "Existen otras reservas activas.", false),
            51410 => ("PALLET_CLOSER_NOT_PRODUCING", "El empleado debe estar produciendo en esta mesa.", false),
            51411 => ("PALLET_PRODUCT_POSTING_GROUP_UNAVAILABLE", "La orden no dispone de grupo contable de producto.", false),
            51412 => ("PREVIOUS_PALLET_OUTPUT_NOT_CONFIRMED", "La salida del palé anterior todavía no está registrada en NAV.", false),
            55400 => ("CORRELATION_ID_REQUIRED", "La correlación es obligatoria.", false),
            55401 => ("PALLET_CLOSE_IDEMPOTENCY_LOCK_UNAVAILABLE", "El cierre no está disponible.", true),
            55402 => ("CORRELATION_ID_ALREADY_USED", "La correlación ya pertenece a otra operación.", false),
            55403 => ("CORRELATION_ID_PARAMETER_MISMATCH", "La correlación no coincide con la solicitud.", false),
            55404 => ("PALLET_CLOSE_INCOMPLETE", "El cierre no está disponible.", true),
            _ => default
        };
        return rejection != default;
    }
}
