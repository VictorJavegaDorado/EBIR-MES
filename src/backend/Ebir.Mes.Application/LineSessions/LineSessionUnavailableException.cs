namespace Ebir.Mes.Application.LineSessions;

public sealed class LineSessionUnavailableException(
    string message,
    Exception? innerException = null)
    : Exception(message, innerException);
