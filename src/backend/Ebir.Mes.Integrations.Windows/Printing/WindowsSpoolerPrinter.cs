using System.Text.Json;
using Ebir.Mes.Application.Printing;

namespace Ebir.Mes.Integrations.Printing;

public sealed class WindowsSpoolerPrinter : IPrinter
{
    private readonly IReadOnlyDictionary<string, string> printerQueues;
    private readonly IWindowsSpoolerClient client;

    public WindowsSpoolerPrinter(WindowsSpoolerPrinterOptions options)
        : this(options, new WindowsSpoolerClient(options.SubmissionTimeout))
    {
    }

    internal WindowsSpoolerPrinter(
        WindowsSpoolerPrinterOptions options,
        IWindowsSpoolerClient client)
    {
        ArgumentNullException.ThrowIfNull(options);
        ArgumentNullException.ThrowIfNull(client);
        if (options.SubmissionTimeout <= TimeSpan.Zero ||
            options.SubmissionTimeout > TimeSpan.FromMinutes(1))
        {
            throw new ArgumentOutOfRangeException(
                nameof(options),
                "The Windows spooler submission timeout must be between one tick and one minute.");
        }
        printerQueues = new Dictionary<string, string>(
            options.PrinterQueues,
            StringComparer.OrdinalIgnoreCase);
        this.client = client;
    }

    public async Task<PrintReceipt> PrintAsync(
        PrintJobRecord job,
        CancellationToken cancellationToken)
    {
        if (!OperatingSystem.IsWindows())
            throw new PrinterUnavailableException(
                "Windows spooler printing is available only on Windows.");
        if (!string.Equals(job.TemplateCode, "PALET", StringComparison.Ordinal) ||
            job.TemplateVersion != 1)
        {
            throw new PrinterUnavailableException(
                $"Unsupported Windows spooler template {job.TemplateCode}/{job.TemplateVersion}.");
        }
        if (job.Copies is < 1 or > 10)
            throw new PrinterUnavailableException("The requested copy count is outside the allowed range.");
        if (!printerQueues.TryGetValue(job.PrinterCode, out var printerQueueName) ||
            string.IsNullOrWhiteSpace(printerQueueName))
        {
            throw new PrinterUnavailableException(
                "The requested MES printer has no explicit Windows queue mapping.");
        }

        try
        {
            using var payload = JsonDocument.Parse(job.LabelDataJson);
            var label = ReadLabel(payload.RootElement);
            var documentName = $"MES-{job.PrintJobUid:N}";
            await client.SubmitAsync(
                printerQueueName.Trim(),
                documentName,
                label,
                job.Copies,
                cancellationToken);
            return new(JsonSerializer.Serialize(new
            {
                adapter = nameof(WindowsSpoolerPrinter),
                queue = printerQueueName.Trim(),
                document = documentName,
                copies = job.Copies
            }));
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (PrinterUnavailableException)
        {
            throw;
        }
        catch (Exception exception) when (
            exception is JsonException or InvalidOperationException or FormatException)
        {
            throw new PrinterUnavailableException(
                "The persisted pallet label is invalid.",
                exception);
        }
    }

    private static PalletLabelContent ReadLabel(JsonElement payload) => new(
        RequiredText(payload, "codigo_palet"),
        RequiredText(payload, "numero_orden"),
        RequiredText(payload, "producto_codigo"),
        RequiredText(payload, "producto_descripcion"),
        RequiredText(payload, "grupo_contable_producto"),
        RequiredText(payload, "lote"),
        RequiredPositiveDecimal(payload, "cantidad"),
        RequiredText(payload, "linea_nombre"));

    private static string RequiredText(JsonElement payload, string name)
    {
        if (!payload.TryGetProperty(name, out var value) ||
            value.ValueKind != JsonValueKind.String ||
            string.IsNullOrWhiteSpace(value.GetString()))
        {
            throw new PrinterUnavailableException(
                $"The label does not contain required field {name}.");
        }
        return value.GetString()!.Trim();
    }

    private static decimal RequiredPositiveDecimal(JsonElement payload, string name)
    {
        if (!payload.TryGetProperty(name, out var value) ||
            value.ValueKind != JsonValueKind.Number ||
            !value.TryGetDecimal(out var result) || result <= 0)
        {
            throw new PrinterUnavailableException(
                $"The label does not contain a positive numeric field {name}.");
        }
        return result;
    }
}
