namespace Ebir.Mes.Application.LineIdentification;

public sealed class LineIdentificationUnavailableException : Exception
{
    public LineIdentificationUnavailableException(string message)
        : base(message)
    {
    }

    public LineIdentificationUnavailableException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

