namespace Ebir.Mes.Application.Printing.LabelControl;

public sealed class LabelControlUnavailableException(
    string message,
    Exception? innerException = null) : Exception(message, innerException);
