namespace Ebir.Mes.Application.Rfid;

public sealed class RfidCredentialInvalidException(string message)
    : Exception(message);
