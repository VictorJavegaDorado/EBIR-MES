using System.Text.Json;
using Ebir.Mes.Application.Printing;
using Ebir.Mes.Integrations.Printing;
using Xunit;

namespace Ebir.Mes.Integrations.Windows.Tests.Printing;

public sealed class WindowsSpoolerPrinterTests
{
    [Fact]
    public async Task PrintAsync_submits_exact_pallet_to_explicit_queue()
    {
        var client = new RecordingClient();
        var printer = Printer(client);

        var receipt = await printer.PrintAsync(Job(), CancellationToken.None);

        Assert.Equal("MES-11111111111111111111111111111111", client.DocumentName);
        Assert.Equal("PILOT QUEUE", client.PrinterQueueName);
        Assert.Equal((short)1, client.Copies);
        Assert.NotNull(client.Label);
        Assert.Equal("FL26-00004/000003", client.Label.PalletCode);
        Assert.Equal("P_MATPRIMA", client.Label.ProductPostingGroup);
        Assert.Equal("Linea piloto", client.Label.AssemblyLineName);
        using var technicalData = JsonDocument.Parse(receipt.TechnicalDataJson);
        Assert.Equal(
            nameof(WindowsSpoolerPrinter),
            technicalData.RootElement.GetProperty("adapter").GetString());
    }

    [Fact]
    public async Task PrintAsync_rejects_printer_without_explicit_mapping()
    {
        var printer = Printer(new RecordingClient());

        await Assert.ThrowsAsync<PrinterUnavailableException>(() =>
            printer.PrintAsync(Job(printerCode: "UNKNOWN"), CancellationToken.None));
    }

    [Fact]
    public async Task PrintAsync_rejects_missing_functional_label_field()
    {
        var printer = Printer(new RecordingClient());
        var job = Job(labelDataJson: JsonSerializer.Serialize(new
        {
            codigo_palet = "FL26-00004/000003",
            numero_orden = "FL26-00004",
            producto_codigo = "27920LG",
            producto_descripcion = "Producto piloto",
            grupo_contable_producto = "P_MATPRIMA",
            lote = "FL2600004",
            cantidad = 20
        }));

        await Assert.ThrowsAsync<PrinterUnavailableException>(() =>
            printer.PrintAsync(job, CancellationToken.None));
    }

    private static WindowsSpoolerPrinter Printer(RecordingClient client) => new(
        new WindowsSpoolerPrinterOptions(
            new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
            {
                ["PRN-VRETTI-01"] = "PILOT QUEUE"
            },
            TimeSpan.FromSeconds(15)),
        client);

    private static PrintJobRecord Job(
        string printerCode = "PRN-VRETTI-01",
        string? labelDataJson = null) => new(
        14,
        Guid.Parse("11111111-1111-1111-1111-111111111111"),
        30,
        Guid.Parse("22222222-2222-2222-2222-222222222222"),
        10,
        printerCode,
        "VRETTI 420B",
        "PALET",
        1,
        labelDataJson ?? JsonSerializer.Serialize(new
        {
            codigo_palet = "FL26-00004/000003",
            numero_orden = "FL26-00004",
            producto_codigo = "27920LG",
            producto_descripcion = "Producto piloto",
            grupo_contable_producto = "P_MATPRIMA",
            lote = "FL2600004",
            cantidad = 20,
            linea_nombre = "Linea piloto"
        }),
        1,
        1);

    private sealed class RecordingClient : IWindowsSpoolerClient
    {
        public string? PrinterQueueName { get; private set; }
        public string? DocumentName { get; private set; }
        public PalletLabelContent? Label { get; private set; }
        public short Copies { get; private set; }

        public Task SubmitAsync(
            string printerQueueName,
            string documentName,
            PalletLabelContent label,
            short copies,
            CancellationToken cancellationToken)
        {
            PrinterQueueName = printerQueueName;
            DocumentName = documentName;
            Label = label;
            Copies = copies;
            return Task.CompletedTask;
        }
    }
}
