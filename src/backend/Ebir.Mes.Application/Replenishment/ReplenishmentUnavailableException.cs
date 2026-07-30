namespace Ebir.Mes.Application.Replenishment;

public sealed class ReplenishmentUnavailableException : Exception
{
    public ReplenishmentUnavailableException(
        string message,
        Exception? innerException = null)
        : base(message, innerException)
    {
    }
}
