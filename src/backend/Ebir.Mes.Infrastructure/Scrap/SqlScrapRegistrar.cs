using System.Data;
using Ebir.Mes.Application.Scrap;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.Scrap;

public sealed class SqlScrapRegistrar(string? connectionString) : IScrapRegistrar
{
    public async Task<RegisteredScrapRecord> RegisterAsync(
        RegisterScrapCommand request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
            throw new ScrapUnavailableException(
                "La conexión de EBIR_MES_TEST no está configurada.");
        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new SqlCommand("[log].registrar_scrap", connection)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 10
            };
            command.Parameters.Add("@sesion_linea_id", SqlDbType.BigInt).Value =
                request.LineSessionId;
            command.Parameters.Add("@componente_orden_id", SqlDbType.BigInt).Value =
                request.OrderComponentId;
            command.Parameters.Add("@motivo_scrap_id", SqlDbType.SmallInt).Value =
                request.ScrapReasonId;
            command.Parameters.Add("@cantidad", SqlDbType.Int).Value = request.Quantity;
            command.Parameters.Add(
                "@descripcion",
                SqlDbType.NVarChar,
                RegisterScrap.MaximumDescriptionLength).Value =
                request.Description is null ? DBNull.Value : request.Description;
            command.Parameters.Add("@registrado_por_empleado_id", SqlDbType.BigInt).Value =
                request.RegisteredByEmployeeId;
            command.Parameters.Add("@correlacion_id", SqlDbType.UniqueIdentifier).Value =
                request.CorrelationId;
            var scrapId = command.Parameters.Add("@scrap_id", SqlDbType.BigInt);
            scrapId.Direction = ParameterDirection.Output;
            var navOperationId =
                command.Parameters.Add("@operacion_nav_id", SqlDbType.BigInt);
            navOperationId.Direction = ParameterDirection.Output;
            await command.ExecuteNonQueryAsync(cancellationToken);
            return new(
                Convert.ToInt64(scrapId.Value),
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
                "No se ha podido registrar el scrap.", exception);
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
            55000 => ("LINE_SESSION_ID_REQUIRED", "La sesión es obligatoria."),
            55001 => ("ORDER_COMPONENT_ID_REQUIRED", "El componente es obligatorio."),
            55002 => ("SCRAP_REASON_ID_REQUIRED", "El motivo de scrap es obligatorio."),
            55003 => ("SCRAP_QUANTITY_INVALID", "La cantidad debe ser positiva."),
            55004 => ("REGISTERED_BY_EMPLOYEE_ID_REQUIRED",
                "El empleado que registra el scrap es obligatorio."),
            55005 => ("CORRELATION_ID_REQUIRED", "La correlación es obligatoria."),
            55006 => ("SCRAP_IDEMPOTENCY_LOCK_UNAVAILABLE",
                "No se pudo asegurar la idempotencia del registro."),
            55007 => ("CORRELATION_ID_ALREADY_USED",
                "La correlación ya pertenece a otra operación."),
            55008 => ("PREVIOUS_SCRAP_REGISTRATION_INCOMPLETE",
                "El registro anterior está incompleto."),
            55009 => ("LINE_SESSION_NOT_ACTIVE", "La sesión no existe o ya finalizó."),
            55010 => ("LINE_SESSION_STATE_NOT_ALLOWED_FOR_SCRAP",
                "La sesión no admite registrar scrap."),
            55011 => ("ORDER_STATE_NOT_ALLOWED_FOR_SCRAP",
                "La orden no admite registrar scrap."),
            55012 => ("SCRAP_REGISTRAR_ROLE_NOT_ALLOWED",
                "El registro requiere operario o supervisor activo."),
            55013 => ("ORDER_COMPONENT_NOT_FOUND",
                "El componente no pertenece a la orden de la sesión."),
            55014 => ("SCRAP_REASON_NOT_ACTIVE",
                "El motivo de scrap no existe o no está activo."),
            55015 => ("SCRAP_DESCRIPTION_REQUIRED",
                "El motivo seleccionado requiere descripción."),
            55016 => ("CORRELATION_ID_PARAMETER_MISMATCH",
                "La correlación ya se utilizó con parámetros diferentes."),
            _ => default
        };
        return rejection != default;
    }
}
