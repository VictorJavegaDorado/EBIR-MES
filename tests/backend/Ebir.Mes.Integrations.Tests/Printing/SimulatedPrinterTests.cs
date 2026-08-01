using System.Text.Json;
using Ebir.Mes.Application.Printing;
using Ebir.Mes.Integrations.Printing;
using Xunit;

namespace Ebir.Mes.Integrations.Tests.Printing;

public sealed class SimulatedPrinterTests : IDisposable
{
    private readonly string outputDirectory = Path.Combine(
        Path.GetTempPath(),
        $"ebir-mes-printing-{Guid.NewGuid():N}");

    [Fact]
    public async Task PrintAsync_writes_idempotent_receipt_with_NAV_lot()
    {
        var job = Job("FL2002277");
        var printer = new SimulatedPrinter(new(outputDirectory));

        var first = await printer.PrintAsync(job, CancellationToken.None);
        var second = await printer.PrintAsync(job, CancellationToken.None);

        var file = Assert.Single(Directory.GetFiles(outputDirectory));
        using var receipt = JsonDocument.Parse(await File.ReadAllTextAsync(file));
        Assert.True(receipt.RootElement.GetProperty("simulated").GetBoolean());
        Assert.Equal(
            "FL2002277",
            receipt.RootElement.GetProperty("label").GetProperty("lote").GetString());
        Assert.Equal(first, second);
    }

    [Fact]
    public async Task PrintAsync_rejects_label_without_lot()
    {
        var printer = new SimulatedPrinter(new(outputDirectory));

        await Assert.ThrowsAsync<PrinterUnavailableException>(
            () => printer.PrintAsync(Job(""), CancellationToken.None));
        Assert.False(Directory.Exists(outputDirectory));
    }

    public void Dispose()
    {
        if (Directory.Exists(outputDirectory))
            Directory.Delete(outputDirectory, recursive: true);
        GC.SuppressFinalize(this);
    }

    private static PrintJobRecord Job(string lot) => new(
        7,
        Guid.Parse("11111111-1111-1111-1111-111111111111"),
        8,
        Guid.Parse("22222222-2222-2222-2222-222222222222"),
        9,
        "ZZTEST-PRN",
        "SIMULADA",
        "PALET",
        1,
        JsonSerializer.Serialize(new
        {
            codigo_palet = "ZZ-PALLET-01",
            numero_orden = "FL20-02277",
            producto_codigo = "27979CI",
            lote = lot,
            cantidad = 10
        }),
        1,
        1);
}
