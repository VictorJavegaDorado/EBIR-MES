using System.Diagnostics;
using System.Net;
using System.Text;
using System.Xml;
using System.Xml.Linq;
using Ebir.Mes.Application.ProductionOrders;

namespace Ebir.Mes.Integrations.Navision;

internal sealed class NavisionSoapPageReader(
    HttpClient httpClient,
    NavisionOptions options)
{
    private const string SoapEnvelopeNamespace =
        "http://schemas.xmlsoap.org/soap/envelope/";
    private static readonly ActivitySource ActivitySource =
        new("Ebir.Mes.Integrations.Navision");

    public async Task<XDocument> ReadMultipleAsync(
        NavisionPage page,
        IReadOnlyList<NavisionFilter> filters,
        int maximumRecords,
        CancellationToken cancellationToken)
    {
        using var activity = ActivitySource.StartActivity(
            "navision.page.read-multiple",
            ActivityKind.Client);
        activity?.SetTag("navision.page", page.Name);
        activity?.SetTag("navision.company", options.Company);
        activity?.SetTag("navision.maximum_records", maximumRecords);

        for (var attempt = 1; attempt <= options.MaximumReadAttempts; attempt++)
        {
            try
            {
                using var request = CreateRequest(page, filters, maximumRecords);
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
                    var document = ParseResponse(responseBody);
                    XNamespace pageNamespace = page.Namespace;
                    activity?.SetTag(
                        "navision.record_count",
                        document.Descendants(pageNamespace + page.Name).Count());
                    return document;
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
        NavisionPage page,
        IReadOnlyList<NavisionFilter> filters,
        int maximumRecords)
    {
        XNamespace soap = SoapEnvelopeNamespace;
        XNamespace pageNamespace = page.Namespace;
        var body = new XElement(pageNamespace + "ReadMultiple");
        foreach (var filter in filters)
        {
            body.Add(
                new XElement(
                    pageNamespace + "filter",
                    new XElement(pageNamespace + "Field", filter.Field),
                    new XElement(pageNamespace + "Criteria", filter.Criteria)));
        }

        body.Add(new XElement(pageNamespace + "bookmarkKey", string.Empty));
        body.Add(new XElement(pageNamespace + "setSize", maximumRecords));
        var envelope = new XDocument(
            new XElement(
                soap + "Envelope",
                new XElement(soap + "Body", body)));

        var company = Uri.EscapeDataString(options.Company);
        var endpoint = new Uri(
            options.ServiceRoot,
            $"{company}/Page/{page.Name}");
        var request = new HttpRequestMessage(HttpMethod.Post, endpoint)
        {
            Content = new StringContent(
                envelope.ToString(SaveOptions.DisableFormatting),
                Encoding.UTF8,
                "text/xml")
        };
        request.Headers.TryAddWithoutValidation(
            "SOAPAction",
            page.Namespace + ":ReadMultiple");
        return request;
    }

    private static XDocument ParseResponse(string responseBody)
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
            var fault = document.Descendants(soap + "Fault").SingleOrDefault();
            if (fault is not null)
            {
                var faultCode = fault.Element("faultcode")?.Value;
                throw new ProductionOrderSourceUnavailableException(
                    string.IsNullOrWhiteSpace(faultCode)
                        ? "NAV rejected the production order query."
                        : $"NAV rejected the production order query ({faultCode}).");
            }

            return document;
        }
        catch (ProductionOrderSourceUnavailableException)
        {
            throw;
        }
        catch (Exception exception)
            when (exception is XmlException or InvalidOperationException)
        {
            throw new ProductionOrderSourceUnavailableException(
                "NAV returned an invalid production order response.",
                exception);
        }
    }

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
            return document
                .Descendants(soap + "Fault")
                .Elements("faultcode")
                .SingleOrDefault()
                ?.Value;
        }
        catch (Exception exception)
            when (exception is XmlException or InvalidOperationException)
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

internal sealed record NavisionPage(string Name, string Namespace);

internal sealed record NavisionFilter(string Field, string Criteria);
