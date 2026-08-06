namespace Ebir.Mes.Application.NavisionOutput;

public sealed class NavisionPalletOutputQueueUnavailableException(
    string message,
    Exception? innerException = null) : Exception(message, innerException);
