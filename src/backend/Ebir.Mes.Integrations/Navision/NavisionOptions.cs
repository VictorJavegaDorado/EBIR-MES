namespace Ebir.Mes.Integrations.Navision;

public sealed record NavisionOptions
{
    private const string AllowedHost = "navision2.ebir.local";
    private const int AllowedPort = 7147;
    private const string AllowedPath = "/EbirTest/WS/";
    private const string AllowedCompany = "EBIR";
    public const int MaximumAllowedReadAttempts = 3;

    public NavisionOptions(
        Uri serviceRoot,
        string company,
        TimeSpan requestTimeout,
        int maximumReadAttempts = MaximumAllowedReadAttempts)
    {
        ArgumentNullException.ThrowIfNull(serviceRoot);
        ArgumentNullException.ThrowIfNull(company);

        if (!serviceRoot.IsAbsoluteUri)
        {
            throw new ArgumentException(
                "La raiz NAV debe ser la raiz SOAP exacta de EbirTest en NAVISION2.",
                nameof(serviceRoot));
        }

        var normalizedServiceRoot = EnsureTrailingSlash(serviceRoot);
        if (!string.Equals(normalizedServiceRoot.Scheme, Uri.UriSchemeHttp,
                StringComparison.OrdinalIgnoreCase)
            || !string.Equals(normalizedServiceRoot.IdnHost, AllowedHost,
                StringComparison.OrdinalIgnoreCase)
            || normalizedServiceRoot.Port != AllowedPort
            || !string.Equals(
                Uri.UnescapeDataString(normalizedServiceRoot.AbsolutePath),
                AllowedPath,
                StringComparison.OrdinalIgnoreCase)
            || !string.IsNullOrEmpty(normalizedServiceRoot.Query)
            || !string.IsNullOrEmpty(normalizedServiceRoot.Fragment)
            || !string.IsNullOrEmpty(normalizedServiceRoot.UserInfo))
        {
            throw new ArgumentException(
                "La raiz NAV debe ser la raiz SOAP exacta de EbirTest en NAVISION2.",
                nameof(serviceRoot));
        }

        var normalizedCompany = company.Trim();
        if (!string.Equals(normalizedCompany, AllowedCompany,
                StringComparison.Ordinal))
        {
            throw new ArgumentException(
                "La empresa NAV debe ser EBIR.",
                nameof(company));
        }

        if (requestTimeout <= TimeSpan.Zero ||
            requestTimeout > TimeSpan.FromMinutes(2))
        {
            throw new ArgumentOutOfRangeException(
                nameof(requestTimeout),
                "NAV request timeout must be between zero and two minutes.");
        }

        if (maximumReadAttempts < 1 ||
            maximumReadAttempts > MaximumAllowedReadAttempts)
        {
            throw new ArgumentOutOfRangeException(
                nameof(maximumReadAttempts),
                $"NAV read attempts must be between 1 and {MaximumAllowedReadAttempts}.");
        }

        ServiceRoot = normalizedServiceRoot;
        Company = normalizedCompany;
        RequestTimeout = requestTimeout;
        MaximumReadAttempts = maximumReadAttempts;
    }

    public Uri ServiceRoot { get; }

    public string Company { get; }

    public TimeSpan RequestTimeout { get; }

    public int MaximumReadAttempts { get; }

    private static Uri EnsureTrailingSlash(Uri serviceRoot)
    {
        var value = serviceRoot.AbsoluteUri;
        return value.EndsWith("/", StringComparison.Ordinal)
            ? serviceRoot
            : new Uri(value + '/', UriKind.Absolute);
    }
}
