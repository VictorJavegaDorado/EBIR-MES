using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Text;
using System.Xml;
using System.Xml.Linq;
using Ebir.Mes.Application.ProductionOrders;

namespace Ebir.Mes.Integrations.Navision;

public sealed class NavisionProductionOrderSource(
    HttpClient httpClient,
    NavisionOptions options)
    : IProductionOrderSource
{
    public const int MaximumPageSize = 100;

    private const string PageName = "WS_CPP_ProdOrderList";
    private const string PageNamespace =
        "urn:microsoft-dynamics-schemas/page/ws_cpp_prodorderlist";
    private const string SoapEnvelopeNamespace =
        "http://schemas.xmlsoap.org/soap/envelope/";
    private const string SoapAction = PageNamespace + ":ReadMultiple";
    private static readonly ActivitySource ActivitySource =
        new("Ebir.Mes.Integrations.Navision");

    public async Task<IReadOnlyList<ProductionOrderRecord>> ReadAsync(
        ProductionOrderStatus status,
        int maximumRecords,
        CancellationToken cancellationToken)
    {
        if (maximumRecords < 1 || maximumRecords > MaximumPageSize)
        {
            throw new ArgumentOutOfRangeException(
                nameof(maximumRecords),
                $"The NAV page size must be between 1 and {MaximumPageSize}.");
        }

        using var activity = ActivitySource.StartActivity(
            "navision.production-orders.read",
            ActivityKind.Client);
        activity?.SetTag("navision.page", PageName);
        activity?.SetTag("navision.company", options.Company);
        activity?.SetTag("navision.status", status.ToString());
        activity?.SetTag("navision.maximum_records", maximumRecords);

        for (var attempt = 1; attempt <= options.MaximumReadAttempts; attempt++)
        {
            try
            {
                using var request = CreateRequest(status, maximumRecords);
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
                    var records = ParseResponse(responseBody);
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

                throw CreateUnavailableException(
                    response.StatusCode,
                    responseBody);
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
                    "NAV did not answer within the configured timeout.",
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
                    "NAV production orders are currently unavailable.",
                    exception);
            }
        }

        throw new UnreachableException();
    }

    private HttpRequestMessage CreateRequest(
        ProductionOrderStatus status,
        int maximumRecords)
    {
        XNamespace soap = SoapEnvelopeNamespace;
        XNamespace page = PageNamespace;
        var envelope = new XDocument(
            new XElement(
                soap + "Envelope",
                new XElement(
                    soap + "Body",
                    new XElement(
                        page + "ReadMultiple",
                        new XElement(
                            page + "filter",
                            new XElement(page + "Field", "Status"),
                            new XElement(page + "Criteria", ToNavisionStatus(status))),
                        new XElement(page + "bookmarkKey", string.Empty),
                        new XElement(page + "setSize", maximumRecords)))));

        var company = Uri.EscapeDataString(options.Company);
        var endpoint = new Uri(
            options.ServiceRoot,
            $"{company}/Page/{PageName}");
        var request = new HttpRequestMessage(HttpMethod.Post, endpoint)
        {
            Content = new StringContent(
                envelope.ToString(SaveOptions.DisableFormatting),
                Encoding.UTF8,
                "text/xml")
        };
        request.Headers.TryAddWithoutValidation("SOAPAction", SoapAction);
        return request;
    }

    private static IReadOnlyList<ProductionOrderRecord> ParseResponse(
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
            XNamespace soap = SoapEnvelopeNamespace;
            XNamespace page = PageNamespace;

            var fault = document.Descendants(soap + "Fault").SingleOrDefault();
            if (fault is not null)
            {
                var faultCode = fault.Element("faultcode")?.Value;
                throw new ProductionOrderSourceUnavailableException(
                    string.IsNullOrWhiteSpace(faultCode)
                        ? "NAV rejected the production order query."
                        : $"NAV rejected the production order query ({faultCode}).");
            }

            return document
                .Descendants(page + "WS_CPP_ProdOrderList")
                .Select(record => MapRecord(record, page))
                .ToArray();
        }
        catch (ProductionOrderSourceUnavailableException)
        {
            throw;
        }
        catch (Exception exception)
            when (exception is XmlException or FormatException or InvalidOperationException)
        {
            throw new ProductionOrderSourceUnavailableException(
                "NAV returned an invalid production order response.",
                exception);
        }
    }

    private static ProductionOrderRecord MapRecord(
        XElement record,
        XNamespace page)
    {
        var orderNumber = RequiredValue(record, page + "No");
        var status = ParseStatus(RequiredValue(record, page + "Status"));

        return new ProductionOrderRecord(
            orderNumber,
            status,
            Value(record, page + "Description"),
            Value(record, page + "Source_No"),
            Value(record, page + "Routing_No"),
            ParseDecimal(Value(record, page + "Quantity")),
            Value(record, page + "Location_Code"),
            ParseDate(Value(record, page + "Starting_Date")),
            ParseDate(Value(record, page + "Ending_Date")),
            ParseDate(Value(record, page + "Due_Date")));
    }

    private static string RequiredValue(XElement record, XName name)
    {
        var value = Value(record, name);
        return string.IsNullOrWhiteSpace(value)
            ? throw new FormatException($"NAV response is missing {name.LocalName}.")
            : value;
    }

    private static string Value(XElement record, XName name) =>
        record.Element(name)?.Value.Trim() ?? string.Empty;

    private static decimal ParseDecimal(string value) =>
        string.IsNullOrWhiteSpace(value)
            ? 0m
            : decimal.Parse(value, NumberStyles.Number, CultureInfo.InvariantCulture);

    private static DateOnly? ParseDate(string value) =>
        string.IsNullOrWhiteSpace(value)
            ? null
            : DateOnly.ParseExact(value, "yyyy-MM-dd", CultureInfo.InvariantCulture);

    private static ProductionOrderStatus ParseStatus(string value) =>
        value switch
        {
            "Simulated" => ProductionOrderStatus.Simulated,
            "Planned" => ProductionOrderStatus.Planned,
            "Firm_Planned" => ProductionOrderStatus.FirmPlanned,
            "Released" => ProductionOrderStatus.Released,
            "Finished" => ProductionOrderStatus.Finished,
            _ => throw new FormatException(
                $"Unknown NAV production order status: {value}.")
        };

    private static string ToNavisionStatus(ProductionOrderStatus status) =>
        status switch
        {
            ProductionOrderStatus.Simulated => "Simulated",
            ProductionOrderStatus.Planned => "Planned",
            ProductionOrderStatus.FirmPlanned => "Firm_Planned",
            ProductionOrderStatus.Released => "Released",
            ProductionOrderStatus.Finished => "Finished",
            _ => throw new ArgumentOutOfRangeException(nameof(status))
        };

    private static bool IsTransient(HttpStatusCode statusCode) =>
        statusCode is HttpStatusCode.RequestTimeout or
            HttpStatusCode.TooManyRequests ||
        (int)statusCode >= 500;

    private static ProductionOrderSourceUnavailableException
        CreateUnavailableException(
            HttpStatusCode statusCode,
            string responseBody)
    {
        var faultCode = TryReadFaultCode(responseBody);
        var detail = string.IsNullOrWhiteSpace(faultCode)
            ? $"HTTP {(int)statusCode}"
            : faultCode;
        return new ProductionOrderSourceUnavailableException(
            $"NAV rejected the production order query ({detail}).");
    }

    private static string? TryReadFaultCode(string responseBody)
    {
        try
        {
            var document = XDocument.Parse(responseBody);
            XNamespace soap = SoapEnvelopeNamespace;
            return document
                .Descendants(soap + "Fault")
                .Elements("faultcode")
                .SingleOrDefault()
                ?.Value;
        }
        catch (XmlException)
        {
            return null;
        }
    }

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
