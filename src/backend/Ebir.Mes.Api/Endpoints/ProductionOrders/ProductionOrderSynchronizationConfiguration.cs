using Ebir.Mes.Application.ProductionOrders;
using Ebir.Mes.Integrations.Navision;

namespace Ebir.Mes.Api.Endpoints.ProductionOrders;

internal sealed record ProductionOrderSynchronizationConfiguration(
    bool Enabled,
    bool PreparationEnabled,
    string EnvironmentCode,
    string CompanyCode,
    string ServiceRoot,
    int RequestTimeoutSeconds,
    int MaximumReadAttempts)
{
    internal const string HttpClientName = "NavisionProductionOrders";

    internal static ProductionOrderSynchronizationConfiguration Read(
        IConfiguration configuration)
    {
        var section = configuration.GetSection("Navision");
        return new(
            section.GetValue<bool>("ProductionOrderSynchronizationEnabled"),
            section.GetValue<bool>("ProductionOrderPreparationEnabled"),
            section["Environment"]?.Trim() ?? string.Empty,
            section["Company"]?.Trim() ?? string.Empty,
            section["ServiceRoot"]?.Trim() ?? string.Empty,
            section.GetValue("RequestTimeoutSeconds", 30),
            section.GetValue("MaximumReadAttempts", 3));
    }

    internal NavisionOptions CreateNavisionOptions()
    {
        if ((!Enabled && !PreparationEnabled) ||
            string.IsNullOrWhiteSpace(EnvironmentCode) ||
            string.IsNullOrWhiteSpace(CompanyCode) ||
            !Uri.TryCreate(ServiceRoot, UriKind.Absolute, out var serviceRoot))
        {
            throw Unavailable();
        }

        try
        {
            return new NavisionOptions(
                serviceRoot,
                CompanyCode,
                TimeSpan.FromSeconds(RequestTimeoutSeconds),
                MaximumReadAttempts);
        }
        catch (Exception exception)
            when (exception is ArgumentException or OverflowException)
        {
            throw Unavailable(exception);
        }
    }

    private static ProductionOrderSourceUnavailableException Unavailable(
        Exception? innerException = null) =>
        new(
            "La lectura controlada de ?rdenes NAV no est? configurada.",
            innerException);
}
