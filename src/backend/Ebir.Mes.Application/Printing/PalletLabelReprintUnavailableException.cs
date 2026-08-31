namespace Ebir.Mes.Application.Printing;

public sealed class PalletLabelReprintUnavailableException(
    string message,
    Exception? innerException = null) : Exception(message, innerException);
