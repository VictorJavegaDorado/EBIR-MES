using System.Data;
using Ebir.Mes.Application.NavisionOutput;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.NavisionOutput;

public sealed class SqlNavisionPalletOutputQueue(string? connectionString)
    : INavisionPalletOutputQueue
{
    public async Task<NavisionPalletOutputJob?> ReserveNextAsync(
        string workerId,
        CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = StoredProcedure(
            connection,
            "nav.reservar_siguiente_salida_palet");
        command.Parameters.Add("@worker_id", SqlDbType.NVarChar, 100).Value = workerId;
        try
        {
            await using var reader = await command.ExecuteReaderAsync(
                CommandBehavior.SingleRow,
                cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
                return null;
            return new(
                reader.GetInt64(0),
                reader.GetGuid(1),
                reader.GetString(2),
                reader.GetString(3),
                reader.GetString(4),
                reader.GetString(5),
                reader.GetString(6),
                reader.GetString(7),
                reader.GetInt32(8),
                new DateTimeOffset(
                    DateTime.SpecifyKind(reader.GetDateTime(9), DateTimeKind.Utc)),
                reader.GetInt32(10),
                reader.IsDBNull(11) ? null : reader.GetString(11),
                reader.GetBoolean(12),
                reader.IsDBNull(13) ? null : reader.GetInt32(13));
        }
        catch (OperationCanceledException) { throw; }
        catch (SqlException exception)
        {
            throw Unavailable("No se ha podido reservar la salida de palet NAV.", exception);
        }
    }

    public Task CompleteAsync(
        NavisionPalletOutputJob job,
        NavisionPalletOutputReceipt receipt,
        Guid correlationId,
        CancellationToken cancellationToken) =>
        ExecuteResultAsync(
            "nav.completar_salida_palet",
            job,
            receipt,
            correlationId,
            cancellationToken);

    public Task FailAsync(
        NavisionPalletOutputJob job,
        NavisionPalletOutputReceipt receipt,
        CancellationToken cancellationToken) =>
        ExecuteResultAsync(
            "nav.fallar_salida_palet",
            job,
            receipt,
            null,
            cancellationToken);

    private async Task ExecuteResultAsync(
        string procedure,
        NavisionPalletOutputJob job,
        NavisionPalletOutputReceipt receipt,
        Guid? correlationId,
        CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = StoredProcedure(connection, procedure);
        command.Parameters.Add("@operacion_nav_id", SqlDbType.BigInt).Value = job.OperationId;
        command.Parameters.Add("@numero_intento", SqlDbType.Int).Value = job.AttemptNumber;
        command.Parameters.Add("@codigo_http", SqlDbType.Int).Value =
            receipt.HttpStatusCode is null ? DBNull.Value : receipt.HttpStatusCode.Value;
        command.Parameters.Add("@datos_tecnicos", SqlDbType.NVarChar, -1).Value =
            receipt.TechnicalDataJson;

        if (correlationId is not null)
        {
            command.Parameters.Add("@identificador_externo", SqlDbType.NVarChar, 100).Value =
                receipt.ExternalIdentifier!;
            command.Parameters.Add("@correlacion_id", SqlDbType.UniqueIdentifier).Value =
                correlationId.Value;
        }
        else
        {
            command.Parameters.Add("@identificador_externo", SqlDbType.NVarChar, 100).Value =
                string.IsNullOrWhiteSpace(receipt.ExternalIdentifier)
                    ? DBNull.Value
                    : receipt.ExternalIdentifier;
            command.Parameters.Add("@resultado", SqlDbType.NVarChar, 30).Value =
                receipt.Outcome switch
                {
                    NavisionPalletOutputDeliveryOutcome.RetryableFailure =>
                        "ERROR_REINTENTABLE",
                    NavisionPalletOutputDeliveryOutcome.UnknownResult =>
                        "RESULTADO_DESCONOCIDO",
                    NavisionPalletOutputDeliveryOutcome.PermanentFailure =>
                        "ERROR_DEFINITIVO",
                    _ => throw new InvalidOperationException(
                        "Una confirmacion no puede registrarse como fallo.")
                };
        }

        try
        {
            await command.ExecuteNonQueryAsync(cancellationToken);
        }
        catch (OperationCanceledException) { throw; }
        catch (SqlException exception)
        {
            throw Unavailable("No se ha podido registrar el resultado NAV.", exception);
        }
    }

    private async Task<SqlConnection> OpenAsync(CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
            throw Unavailable("La conexion de EBIR_MES_TEST no esta configurada.");
        try
        {
            var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            return connection;
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception exception) when (
            exception is SqlException or ArgumentException or InvalidOperationException)
        {
            throw Unavailable("No se ha podido abrir la cola de salidas NAV.", exception);
        }
    }

    private static SqlCommand StoredProcedure(
        SqlConnection connection,
        string procedure) =>
        new(procedure, connection)
        {
            CommandType = CommandType.StoredProcedure,
            CommandTimeout = 30
        };

    private static NavisionPalletOutputQueueUnavailableException Unavailable(
        string message,
        Exception? exception = null) => new(message, exception);
}
