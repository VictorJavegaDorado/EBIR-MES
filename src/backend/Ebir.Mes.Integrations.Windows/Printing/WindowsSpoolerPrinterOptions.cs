namespace Ebir.Mes.Integrations.Printing;

public sealed record WindowsSpoolerPrinterOptions(
    IReadOnlyDictionary<string, string> PrinterQueues,
    TimeSpan SubmissionTimeout);
