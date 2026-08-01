namespace Ebir.Mes.Application.Printing;

public sealed class PrintJobUnavailableException : Exception
{
    public PrintJobUnavailableException(string message, Exception? inner = null)
        : base(message, inner) { }
}
