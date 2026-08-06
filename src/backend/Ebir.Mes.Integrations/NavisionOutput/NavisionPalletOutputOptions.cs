namespace Ebir.Mes.Integrations.NavisionOutput;

public sealed class NavisionPalletOutputOptions
{
    private const string AllowedHost = "navision.ebir.local";
    private const int AllowedPort = 7147;
    private const string AllowedPath =
        "/EbirTest/WS/EBIR/Page/WS_CPP_SalidasFabrica";

    public NavisionPalletOutputOptions(Uri serviceEndpoint, TimeSpan requestTimeout)
    {
        ArgumentNullException.ThrowIfNull(serviceEndpoint);
        if (!serviceEndpoint.IsAbsoluteUri
            || !string.Equals(serviceEndpoint.Scheme, Uri.UriSchemeHttp,
                StringComparison.OrdinalIgnoreCase)
            || !string.Equals(serviceEndpoint.IdnHost, AllowedHost,
                StringComparison.OrdinalIgnoreCase)
            || serviceEndpoint.Port != AllowedPort
            || !string.Equals(
                Uri.UnescapeDataString(serviceEndpoint.AbsolutePath),
                AllowedPath,
                StringComparison.OrdinalIgnoreCase)
            || !string.IsNullOrEmpty(serviceEndpoint.Query)
            || !string.IsNullOrEmpty(serviceEndpoint.Fragment)
            || !string.IsNullOrEmpty(serviceEndpoint.UserInfo))
        {
            throw new ArgumentException(
                "El endpoint debe ser la pagina SOAP de salidas de EbirTest.",
                nameof(serviceEndpoint));
        }

        if (requestTimeout < TimeSpan.FromSeconds(1)
            || requestTimeout > TimeSpan.FromSeconds(30))
        {
            throw new ArgumentOutOfRangeException(nameof(requestTimeout));
        }

        ServiceEndpoint = serviceEndpoint;
        RequestTimeout = requestTimeout;
    }

    public Uri ServiceEndpoint { get; }

    public TimeSpan RequestTimeout { get; }
}
