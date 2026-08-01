using System.Text.Json;
using Ebir.Mes.Application.Printing;

namespace Ebir.Mes.Integrations.Printing;

public sealed class SimulatedPrinter(SimulatedPrinterOptions options) : IPrinter
{
    public async Task<PrintReceipt> PrintAsync(
        PrintJobRecord job,
        CancellationToken cancellationToken)
    {
        if (!string.Equals(job.TemplateCode, "PALET", StringComparison.Ordinal) ||
            job.TemplateVersion != 1)
        {
            throw new PrinterUnavailableException(
                $"Unsupported simulated template {job.TemplateCode}/{job.TemplateVersion}.");
        }

        try
        {
            using var label = JsonDocument.Parse(job.LabelDataJson);
            ValidateLabel(label.RootElement);
            var outputDirectory = Path.GetFullPath(options.OutputDirectory);
            Directory.CreateDirectory(outputDirectory);
            var outputPath = Path.Combine(
                outputDirectory,
                $"{job.PrintJobUid:D}.print.json");
            var content = JsonSerializer.SerializeToUtf8Bytes(new
            {
                simulated = true,
                job.PrintJobId,
                job.PrintJobUid,
                job.LabelId,
                job.LabelUid,
                job.PrinterCode,
                job.PrinterModel,
                job.TemplateCode,
                job.TemplateVersion,
                job.Copies,
                label = label.RootElement
            }, new JsonSerializerOptions { WriteIndented = true });

            try
            {
                await using var stream = new FileStream(
                    outputPath,
                    FileMode.CreateNew,
                    FileAccess.Write,
                    FileShare.Read,
                    4096,
                    FileOptions.Asynchronous);
                await stream.WriteAsync(content, cancellationToken);
            }
            catch (IOException) when (File.Exists(outputPath))
            {
                var existing = await File.ReadAllBytesAsync(
                    outputPath,
                    cancellationToken);
                if (!existing.AsSpan().SequenceEqual(content))
                {
                    throw new PrinterUnavailableException(
                        "The simulated receipt already exists with different content.");
                }
            }

            return new(JsonSerializer.Serialize(new
            {
                adapter = nameof(SimulatedPrinter),
                simulated = true,
                receipt = Path.GetFileName(outputPath)
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
            exception is IOException or UnauthorizedAccessException or
            JsonException or InvalidOperationException)
        {
            throw new PrinterUnavailableException(
                "The simulated label could not be written.", exception);
        }
    }

    private static void ValidateLabel(JsonElement label)
    {
        foreach (var propertyName in new[]
        {
            "codigo_palet", "numero_orden", "producto_codigo", "lote", "cantidad"
        })
        {
            if (!label.TryGetProperty(propertyName, out var value) ||
                value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined ||
                (value.ValueKind == JsonValueKind.String &&
                 string.IsNullOrWhiteSpace(value.GetString())))
            {
                throw new PrinterUnavailableException(
                    $"The label does not contain required field {propertyName}.");
            }
        }
    }
}
