using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Xml;
using System.Xml.Linq;
using Ebir.Mes.Application.ProductionOrders;

namespace Ebir.Mes.Integrations.Navision;

internal sealed class NavisionODataRoutingReader(
    HttpClient httpClient,
    NavisionOptions options)
{
    private const string RoutingEntity = "WS_CPP_RutaOrdenProduccion";
    private static readonly XNamespace Atom = "http://www.w3.org/2005/Atom";
    private static readonly XNamespace Data =
        "http://schemas.microsoft.com/ado/2007/08/dataservices";
    private static readonly XNamespace Metadata =
        "http://schemas.microsoft.com/ado/2007/08/dataservices/metadata";
    private static readonly ActivitySource ActivitySource =
        new("Ebir.Mes.Integrations.Navision");

    public async Task<IReadOnlyList<ProductionOrderRoutingStepRecord>> ReadAsync(
        string orderNumber,
        int maximumRecords,
        CancellationToken cancellationToken)
    {
        using var activity = ActivitySource.StartActivity(
            "navision.routing.read-odata",
            ActivityKind.Client);
        activity?.SetTag("navision.entity", RoutingEntity);
        activity?.SetTag("navision.company", options.Company);
        activity?.SetTag("navision.maximum_records", maximumRecords);

        var endpoint = CreateEndpoint(orderNumber, maximumRecords);
        for (var attempt = 1; attempt <= options.MaximumReadAttempts; attempt++)
        {
            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Get, endpoint);
                using var timeoutSource =
                    CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                timeoutSource.CancelAfter(options.RequestTimeout);

                using var response = await httpClient.SendAsync(
                    request,
                    HttpCompletionOption.ResponseHeadersRead,
                    timeoutSource.Token);
                var responseBody = await response.Content.ReadAsStringAsync(
                    timeoutSource.Token);

                if (response.IsSuccessStatusCode)
                {
                    var records = Parse(responseBody);
                    activity?.SetTag("navision.record_count", records.Count);
                    return records;
                }

                if (IsTransient(response.StatusCode) &&
                    attempt < options.MaximumReadAttempts)
                {
                    AddRetryEvent(activity, attempt, response.StatusCode);
                    await DelayBeforeRetryAsync(attempt, cancellationToken);
                    continue;
                }

                throw new ProductionOrderSourceUnavailableException(
                    $"NAV rejected the routing query (HTTP {(int)response.StatusCode}).");
            }
            catch (OperationCanceledException exception)
                when (!cancellationToken.IsCancellationRequested)
            {
                if (attempt < options.MaximumReadAttempts)
                {
                    await DelayBeforeRetryAsync(attempt, cancellationToken);
                    continue;
                }

                throw new ProductionOrderSourceUnavailableException(
                    "NAV did not answer the routing query within the configured timeout.",
                    exception);
            }
            catch (HttpRequestException exception)
            {
                if (attempt < options.MaximumReadAttempts)
                {
                    await DelayBeforeRetryAsync(attempt, cancellationToken);
                    continue;
                }

                throw new ProductionOrderSourceUnavailableException(
                    "NAV routing data is currently unavailable.",
                    exception);
            }
        }

        throw new UnreachableException();
    }

    private Uri CreateEndpoint(string orderNumber, int maximumRecords)
    {
        var serviceRoot = options.ServiceRoot;
        const string soapSuffix = "/WS/";
        if (!serviceRoot.AbsolutePath.EndsWith(
                soapSuffix,
                StringComparison.OrdinalIgnoreCase))
        {
            throw new ProductionOrderSourceUnavailableException(
                "NAV service root is not valid for the routing query.");
        }

        var rootBuilder = new UriBuilder(serviceRoot)
        {
            Path = serviceRoot.AbsolutePath[..^soapSuffix.Length] + "/OData/",
            Query = string.Empty,
            Fragment = string.Empty
        };
        var odataRoot = rootBuilder.Uri;
        if (!string.Equals(odataRoot.Scheme, serviceRoot.Scheme, StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(odataRoot.Host, serviceRoot.Host, StringComparison.OrdinalIgnoreCase) ||
            odataRoot.Port != serviceRoot.Port)
        {
            throw new ProductionOrderSourceUnavailableException(
                "NAV service root changed authority while building the routing query.");
        }

        var company = EscapeODataLiteral(options.Company);
        var filter = Uri.EscapeDataString(
            $"Prod_Order_No eq '{EscapeODataLiteral(orderNumber)}'");
        return new Uri(
            odataRoot,
            $"Company('{Uri.EscapeDataString(company)}')/{RoutingEntity}" +
            $"?$filter={filter}&$top={maximumRecords}");
    }

    private static string EscapeODataLiteral(string value) =>
        value.Replace("'", "''", StringComparison.Ordinal);

    private static IReadOnlyList<ProductionOrderRoutingStepRecord> Parse(
        string responseBody)
    {
        try
        {
            using var stringReader = new StringReader(responseBody);
            using var xmlReader = XmlReader.Create(
                stringReader,
                new XmlReaderSettings
                {
                    DtdProcessing = DtdProcessing.Prohibit,
                    XmlResolver = null
                });
            var document = XDocument.Load(xmlReader);
            return document
                .Descendants(Atom + "entry")
                .Select(MapRecord)
                .ToArray();
        }
        catch (Exception exception)
            when (exception is FormatException or
                OverflowException or
                XmlException or
                InvalidOperationException)
        {
            throw new ProductionOrderSourceUnavailableException(
                "NAV returned an invalid routing response.",
                exception);
        }
    }

    private static ProductionOrderRoutingStepRecord MapRecord(XElement entry)
    {
        var properties = entry
            .Descendants(Metadata + "properties")
            .SingleOrDefault() ??
            throw new FormatException("The OData route has no properties.");
        var routingStatus = properties.Element(Data + "Routing_Status");
        var status = routingStatus is null
            ? Value(properties, "Status")
            : routingStatus.Value.Trim();

        return new ProductionOrderRoutingStepRecord(
            RequiredValue(properties, "Prod_Order_No"),
            ParseInt(RequiredValue(properties, "Routing_Reference_No")),
            Value(properties, "Routing_No"),
            RequiredValue(properties, "Operation_No"),
            Value(properties, "Previous_Operation_No"),
            Value(properties, "Next_Operation_No"),
            ParseRoutingType(RequiredValue(properties, "Type")),
            RequiredValue(properties, "No"),
            Value(properties, "Description"),
            ParseDateTime(Value(properties, "Starting_Date_Time")),
            ParseDateTime(Value(properties, "Ending_Date_Time")),
            ParseDecimal(Value(properties, "Setup_Time")),
            ParseDecimal(Value(properties, "Run_Time")),
            ParseDecimal(Value(properties, "Wait_Time")),
            ParseDecimal(Value(properties, "Move_Time")),
            ParseDecimal(Value(properties, "Fixed_Scrap_Quantity")),
            Value(properties, "Routing_Link_Code"),
            ParseDecimal(Value(properties, "Scrap_Factor_Percent")),
            ParseRoutingStatus(status),
            Value(properties, "Location_Code"),
            ParseBool(Value(properties, "IsSigning")));
    }

    private static string RequiredValue(XElement properties, string name)
    {
        var value = Value(properties, name);
        return string.IsNullOrWhiteSpace(value)
            ? throw new FormatException($"The OData route is missing {name}.")
            : value;
    }

    private static string Value(XElement properties, string name) =>
        properties.Element(Data + name)?.Value.Trim() ?? string.Empty;

    private static decimal ParseDecimal(string value) =>
        string.IsNullOrWhiteSpace(value)
            ? 0m
            : decimal.Parse(value, NumberStyles.Number, CultureInfo.InvariantCulture);

    private static int ParseInt(string value) =>
        int.Parse(value, NumberStyles.Integer, CultureInfo.InvariantCulture);

    private static DateTime? ParseDateTime(string value) =>
        string.IsNullOrWhiteSpace(value)
            ? null
            : DateTime.Parse(
                value,
                CultureInfo.InvariantCulture,
                DateTimeStyles.RoundtripKind);

    private static bool ParseBool(string value) =>
        !string.IsNullOrWhiteSpace(value) && bool.Parse(value);

    private static ProductionRoutingStepType ParseRoutingType(string value) =>
        value switch
        {
            "Work_Center" or "Centro trabajo" =>
                ProductionRoutingStepType.WorkCenter,
            "Machine_Center" or "Centro maquina" or "Centro máquina" =>
                ProductionRoutingStepType.MachineCenter,
            _ => throw new FormatException("The OData route has an unknown type.")
        };

    private static ProductionRoutingStatus ParseRoutingStatus(string value) =>
        value switch
        {
            "" or "_blank_" or "Not_Started" or "Lanzada" =>
                ProductionRoutingStatus.NotStarted,
            "Planned" or "Planificada" => ProductionRoutingStatus.Planned,
            "In_Progress" or "En curso" => ProductionRoutingStatus.InProgress,
            "Finished" or "Terminada" or "Finalizada" =>
                ProductionRoutingStatus.Finished,
            _ => throw new FormatException("The OData route has an unknown status.")
        };

    private static bool IsTransient(HttpStatusCode statusCode) =>
        statusCode is HttpStatusCode.RequestTimeout or
            HttpStatusCode.TooManyRequests ||
        (int)statusCode >= 500;

    private static void AddRetryEvent(
        Activity? activity,
        int attempt,
        HttpStatusCode statusCode)
    {
        activity?.AddEvent(new ActivityEvent(
            "navision.read.retry",
            tags: new ActivityTagsCollection
            {
                ["attempt"] = attempt,
                ["http.status_code"] = (int)statusCode
            }));
    }

    private static Task DelayBeforeRetryAsync(
        int attempt,
        CancellationToken cancellationToken) =>
        Task.Delay(TimeSpan.FromMilliseconds(100 * attempt), cancellationToken);
}
