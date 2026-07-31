namespace Ebir.Mes.Integrations.Navision;

public sealed record NavisionOptions
{
    public const int MaximumAllowedReadAttempts = 3;

    public NavisionOptions(
        Uri serviceRoot,
        string company,
        TimeSpan requestTimeout,
        int maximumReadAttempts = MaximumAllowedReadAttempts)
    {
        ArgumentNullException.ThrowIfNull(serviceRoot);

        if (!serviceRoot.IsAbsoluteUri ||
            (serviceRoot.Scheme != Uri.UriSchemeHttp &&
             serviceRoot.Scheme != Uri.UriSchemeHttps))
        {
            throw new ArgumentException(
                "NAV service root must be an absolute HTTP or HTTPS URI.",
                nameof(serviceRoot));
        }

        if (string.IsNullOrWhiteSpace(company))
        {
            throw new ArgumentException("NAV company is required.", nameof(company));
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

        ServiceRoot = EnsureTrailingSlash(serviceRoot);
        Company = company.Trim();
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
