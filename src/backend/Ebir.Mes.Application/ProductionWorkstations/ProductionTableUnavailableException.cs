namespace Ebir.Mes.Application.ProductionWorkstations;

public sealed class ProductionTableUnavailableException(
    string message,
    Exception? innerException = null) : Exception(message, innerException);
