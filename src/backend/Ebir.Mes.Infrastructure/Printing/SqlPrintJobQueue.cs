using System.Data;
using Ebir.Mes.Application.Printing;
using Microsoft.Data.SqlClient;

namespace Ebir.Mes.Infrastructure.Printing;

public sealed class SqlPrintJobQueue(string? connectionString) : IPrintJobQueue
{
    public async Task<PrintJobRecord?> ReserveNextAsync(
        string workerId,
        CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = StoredProcedure(
            connection,
            "imp.reservar_siguiente_trabajo_impresion");
        command.Parameters.Add("@worker_id", SqlDbType.NVarChar, 100).Value = workerId;
        try
        {
            await using var reader = await command.ExecuteReaderAsync(
                CommandBehavior.SingleRow,
                cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
                return null;
            return new(
                reader.GetInt64(0), reader.GetGuid(1), reader.GetInt64(2),
                reader.GetGuid(3), reader.GetInt64(4), reader.GetString(5),
                reader.GetString(6), reader.GetString(7), reader.GetInt32(8),
                reader.GetString(9), reader.GetInt16(10), reader.GetInt32(11));
        }
        catch (OperationCanceledException) { throw; }
        catch (SqlException exception)
        {
            throw new PrintJobUnavailableException(
                "No se ha podido reservar el siguiente trabajo de impresión.",
                exception);
        }
    }

    public Task CompleteAsync(
        PrintJobRecord job,
        Guid correlationId,
        string technicalDataJson,
        CancellationToken cancellationToken) =>
        ExecuteResultAsync(
            "imp.completar_trabajo_impresion",
            job,
            correlationId,
            null,
            technicalDataJson,
            cancellationToken);

    public Task FailAsync(
        PrintJobRecord job,
        string normalizedError,
        string technicalDataJson,
        CancellationToken cancellationToken) =>
        ExecuteResultAsync(
            "imp.fallar_trabajo_impresion",
            job,
            null,
            normalizedError,
            technicalDataJson,
            cancellationToken);

    private async Task ExecuteResultAsync(
        string procedure,
        PrintJobRecord job,
        Guid? correlationId,
        string? error,
        string technicalDataJson,
        CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = StoredProcedure(connection, procedure);
        command.Parameters.Add("@trabajo_impresion_id", SqlDbType.BigInt).Value = job.PrintJobId;
        command.Parameters.Add("@numero_intento", SqlDbType.Int).Value = job.AttemptNumber;
        command.Parameters.Add("@datos_tecnicos", SqlDbType.NVarChar, -1).Value = technicalDataJson;
        if (correlationId is not null)
        {
            command.Parameters.Add("@impresora_utilizada_id", SqlDbType.BigInt).Value =
                job.RequestedPrinterId;
            command.Parameters.Add("@correlacion_id", SqlDbType.UniqueIdentifier).Value =
                correlationId.Value;
        }
        if (error is not null)
            command.Parameters.Add("@error_normalizado", SqlDbType.NVarChar, 1000).Value = error;
        try
        {
            await command.ExecuteNonQueryAsync(cancellationToken);
        }
        catch (OperationCanceledException) { throw; }
        catch (SqlException exception)
        {
            throw new PrintJobUnavailableException(
                "No se ha podido registrar el resultado de impresión.", exception);
        }
    }

    private async Task<SqlConnection> OpenAsync(CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
            throw new PrintJobUnavailableException(
                "La conexión de EBIR_MES_TEST no está configurada.");
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
            throw new PrintJobUnavailableException(
                "No se ha podido abrir la cola de impresión.", exception);
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
}
