namespace Ebir.Mes.Integrations.NavisionOutput;

public sealed class NavisionPalletOutputOptions
{
    private const string AllowedHost = "navision.ebir.local";
    private const int AllowedPort = 7147;
    private const string AllowedPath =
        "/EbirTest/WS/EBIR/Codeunit/WS_CPP_ControlPlanta";
    private const string ODataCompanyPath =
        "/EbirTest/ODataV4/Company('EBIR')/";
    private readonly IReadOnlyDictionary<string, string> assemblyLineMappings;

    public NavisionPalletOutputOptions(
        Uri serviceEndpoint,
        TimeSpan requestTimeout,
        IReadOnlyDictionary<string, string> assemblyLineMappings)
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
        this.assemblyLineMappings = assemblyLineMappings.ToDictionary(
            pair => RequiredMappingValue(pair.Key, nameof(assemblyLineMappings)),
            pair => RequiredMappingValue(pair.Value, nameof(assemblyLineMappings)),
            StringComparer.OrdinalIgnoreCase);
    }

    public Uri ServiceEndpoint { get; }

    public Uri ODataCompanyRoot { get; }

    public TimeSpan RequestTimeout { get; }

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
