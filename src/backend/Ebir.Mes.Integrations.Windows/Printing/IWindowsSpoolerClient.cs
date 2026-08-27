namespace Ebir.Mes.Integrations.Printing;

internal interface IWindowsSpoolerClient
{
    Task SubmitAsync(
        string printerQueueName,
        string documentName,
        PalletLabelContent label,
        short copies,
        CancellationToken cancellationToken);
}
