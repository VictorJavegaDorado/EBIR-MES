using System.Drawing;
using System.Drawing.Printing;
using Ebir.Mes.Application.Printing;

namespace Ebir.Mes.Integrations.Printing;

internal sealed class WindowsSpoolerClient(TimeSpan submissionTimeout) : IWindowsSpoolerClient
{
    public async Task SubmitAsync(
        string printerQueueName,
        string documentName,
        PalletLabelContent label,
        short copies,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var submission = Task.Run(
            () => Submit(printerQueueName, documentName, label, copies),
            CancellationToken.None);
        try
        {
            await submission.WaitAsync(submissionTimeout, cancellationToken);
        }
        catch (TimeoutException exception)
        {
            throw new OperationCanceledException(
                "The Windows spooler submission result is unknown after the configured timeout.",
                exception);
        }
    }

    private static void Submit(
        string printerQueueName,
        string documentName,
        PalletLabelContent label,
        short copies)
    {

        using var document = new PrintDocument
        {
            DocumentName = documentName,
            OriginAtMargins = false,
            PrintController = new StandardPrintController()
        };
        document.PrinterSettings.PrinterName = printerQueueName;
        if (!document.PrinterSettings.IsValid)
            throw new PrinterUnavailableException(
                "The configured Windows printer queue is unavailable.");

        document.PrinterSettings.Copies = copies;
        ConfigurePalletPage(document.DefaultPageSettings);
        document.PrintPage += (_, args) =>
        {
            PalletLabelRenderer.Draw(
                args.Graphics ?? throw new InvalidOperationException(
                    "The Windows spooler did not provide a drawing surface."),
                label);
            args.HasMorePages = false;
        };

        try
        {
            document.Print();
        }
        catch (Exception exception) when (
            exception is InvalidPrinterException or
            System.ComponentModel.Win32Exception or
            System.Runtime.InteropServices.ExternalException or
            ArgumentException or InvalidOperationException)
        {
            throw new PrinterUnavailableException(
                "The label could not be submitted to the Windows print spooler.",
                exception);
        }
    }

    internal static void ConfigurePalletPage(PageSettings pageSettings)
    {
        ArgumentNullException.ThrowIfNull(pageSettings);

        pageSettings.Margins = new Margins(0, 0, 0, 0);
        pageSettings.Landscape = true;
        pageSettings.PaperSize = new PaperSize(
            "EBIR 100x150 mm",
            MillimetresToHundredthsOfInch(100),
            MillimetresToHundredthsOfInch(150));
    }

    private static int MillimetresToHundredthsOfInch(int millimetres) =>
        checked((int)Math.Round(millimetres / 25.4d * 100d));
}
