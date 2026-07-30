namespace Ebir.Mes.Application.Scrap;

public sealed class ScrapUnavailableException : Exception
{
    public ScrapUnavailableException(
        string message,
        Exception? innerException = null)
        : base(message, innerException)
    {
    }
}
