namespace Ebir.Mes.Application.ProductionDashboard;

public sealed class ProductionDashboardUnavailableException : Exception
{
    public ProductionDashboardUnavailableException(string message)
        : base(message)
    {
    }

    public ProductionDashboardUnavailableException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}
