namespace Ebir.Mes.Application.Rfid;

public sealed class RfidIdentificationUnavailableException(
    string message,
    Exception? inner = null) : Exception(message, inner);
