namespace Ebir.Mes.Application.Printing;

public sealed class PrinterUnavailableException : Exception
{
    public PrinterUnavailableException(string message, Exception? inner = null)
        : base(message, inner) { }
}
