namespace Ebir.Mes.Integrations.NavisionOutput;

public sealed class NavisionPalletOutputOptions
{
    private const string AllowedHost = "navision2.ebir.local";
    private const int AllowedPort = 7147;
    private const string AllowedPath =
        "/EbirTest/WS/EBIR/Codeunit/WS_CPP_ControlPlanta";
    private const string ODataCompanyPath =
        "/EbirTest/ODataV4/Company('EBIR')/";
    private static readonly TimeSpan[] DefaultReconciliationObservationDelays =
    [
        TimeSpan.FromSeconds(1),
        TimeSpan.FromSeconds(1),
        TimeSpan.FromSeconds(2),
        TimeSpan.FromSeconds(2),
        TimeSpan.FromSeconds(3),
        TimeSpan.FromSeconds(3),
        TimeSpan.FromSeconds(4),
        TimeSpan.FromSeconds(4),
        TimeSpan.FromSeconds(5),
        TimeSpan.FromSeconds(5)
    ];
    private readonly IReadOnlyDictionary<string, string> assemblyLineMappings;

    public NavisionPalletOutputOptions(
        Uri serviceEndpoint,
        TimeSpan requestTimeout,
        IReadOnlyDictionary<string, string> assemblyLineMappings,
        IReadOnlyList<TimeSpan>? reconciliationObservationDelays = null)
    {
        ArgumentNullException.ThrowIfNull(serviceEndpoint);
        ArgumentNullException.ThrowIfNull(assemblyLineMappings);
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
                "El endpoint debe ser el codeunit SOAP de planta de EbirTest.",
                nameof(serviceEndpoint));
        }

        if (requestTimeout < TimeSpan.FromSeconds(1)
            || requestTimeout > TimeSpan.FromSeconds(30))
        {
            throw new ArgumentOutOfRangeException(nameof(requestTimeout));
        }

        ServiceEndpoint = serviceEndpoint;
        ODataCompanyRoot = new UriBuilder(serviceEndpoint)
        {
            Path = ODataCompanyPath,
            Query = string.Empty,
            Fragment = string.Empty
        }.Uri;
        RequestTimeout = requestTimeout;
        var observationDelays = reconciliationObservationDelays
            ?? DefaultReconciliationObservationDelays;
        if (observationDelays.Count is < 1 or > 20
            || observationDelays.Any(delay =>
                delay <= TimeSpan.Zero || delay > TimeSpan.FromSeconds(10))
            || observationDelays.Aggregate(TimeSpan.Zero, (total, delay) => total + delay)
                > TimeSpan.FromMinutes(1))
        {
            throw new ArgumentOutOfRangeException(
                nameof(reconciliationObservationDelays));
        }
        ReconciliationObservationDelays = Array.AsReadOnly(
            observationDelays.ToArray());
        this.assemblyLineMappings = assemblyLineMappings.ToDictionary(
            pair => RequiredMappingValue(pair.Key, nameof(assemblyLineMappings)),
            pair => RequiredMappingValue(pair.Value, nameof(assemblyLineMappings)),
            StringComparer.OrdinalIgnoreCase);
    }

    public Uri ServiceEndpoint { get; }

    public Uri ODataCompanyRoot { get; }

    public TimeSpan RequestTimeout { get; }

    public IReadOnlyList<TimeSpan> ReconciliationObservationDelays { get; }

    public bool TryResolveAssemblyLine(string mesLineCode, out string assemblyLine) =>
        assemblyLineMappings.TryGetValue(mesLineCode.Trim(), out assemblyLine!);

    private static string RequiredMappingValue(string value, string parameterName)
    {
        if (string.IsNullOrWhiteSpace(value))
            throw new ArgumentException(
                "Los codigos de mapeo de linea no pueden estar vacios.",
                parameterName);
        return value.Trim();
    }
}
