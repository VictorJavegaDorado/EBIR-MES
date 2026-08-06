using System.Globalization;
using System.Net;
using System.Text;
using System.Text.Json;
using System.Xml;
using System.Xml.Linq;
using Ebir.Mes.Application.NavisionOutput;

namespace Ebir.Mes.Integrations.NavisionOutput;

public sealed class NavisionSoapPalletOutputSender(
    HttpClient httpClient,
    NavisionPalletOutputOptions options) : INavisionPalletOutputSender
{
    private const int MaximumResponseBytes = 64 * 1024;
    private const string SoapEnvelopeNamespace =
        "http://schemas.xmlsoap.org/soap/envelope/";
    private const string PageNamespace =
        "urn:microsoft-dynamics-schemas/page/ws_cpp_salidasfabrica";

    public async Task<NavisionPalletOutputReceipt> SendAsync(
        NavisionPalletOutputJob job,
        CancellationToken cancellationToken)
    {
        using var request = CreateRequest(job);
        using var timeout =
            CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(options.RequestTimeout);
        try
        {
            using var response = await httpClient.SendAsync(
                request,
                HttpCompletionOption.ResponseHeadersRead,
                timeout.Token);

            if (response.StatusCode is HttpStatusCode.OK)
                return await ReadConfirmationAsync(job, response, timeout.Token);

            var status = (int)response.StatusCode;
            var outcome = response.StatusCode is HttpStatusCode.RequestTimeout
                or HttpStatusCode.TooManyRequests
                || status >= 500
                ? NavisionPalletOutputDeliveryOutcome.UnknownResult
                : NavisionPalletOutputDeliveryOutcome.PermanentFailure;
            return Receipt(outcome, status);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (OperationCanceledException exception)
        {
            return Receipt(
                NavisionPalletOutputDeliveryOutcome.UnknownResult,
                null,
                exception.GetType().Name);
        }
        catch (HttpRequestException exception)
        {
            return Receipt(
                NavisionPalletOutputDeliveryOutcome.UnknownResult,
                exception.StatusCode is null ? null : (int)exception.StatusCode.Value,
                exception.GetType().Name);
        }
    }

    private HttpRequestMessage CreateRequest(NavisionPalletOutputJob job)
    {
        XNamespace soap = SoapEnvelopeNamespace;
        XNamespace page = PageNamespace;
        var output = new XElement(
            page + "WS_CPP_SalidasFabrica",
            new XElement(page + "Orden", job.OrderNumber),
            new XElement(page + "Producto", job.ProductNumber),
            new XElement(
                page + "Cantidad_salida",
                job.GoodQuantity.ToString(CultureInfo.InvariantCulture)),
            new XElement(
                page + "fecha",
                XmlConvert.ToString(
                    job.ClosedAtUtc.UtcDateTime,
                    XmlDateTimeSerializationMode.Utc)),
            new XElement(page + "Tipo", "Salida"));
        var document = new XDocument(
            new XElement(
                soap + "Envelope",
                new XElement(
                    soap + "Body",
                    new XElement(page + "Create", output))));
        var request = new HttpRequestMessage(HttpMethod.Post, options.ServiceEndpoint)
        {
            Content = new StringContent(
                document.ToString(SaveOptions.DisableFormatting),
                Encoding.UTF8,
                "text/xml")
        };
        request.Headers.TryAddWithoutValidation("SOAPAction", PageNamespace + ":Create");
        return request;
    }

    private static async Task<NavisionPalletOutputReceipt> ReadConfirmationAsync(
        NavisionPalletOutputJob job,
        HttpResponseMessage response,
        CancellationToken cancellationToken)
    {
        var status = (int)response.StatusCode;
        if (response.Content.Headers.ContentLength > MaximumResponseBytes)
            return Receipt(NavisionPalletOutputDeliveryOutcome.UnknownResult, status);

        try
        {
            var body = await response.Content.ReadAsByteArrayAsync(cancellationToken);
            if (body.Length == 0 || body.Length > MaximumResponseBytes)
                return Receipt(NavisionPalletOutputDeliveryOutcome.UnknownResult, status);

            using var stream = new MemoryStream(body, writable: false);
            using var reader = XmlReader.Create(
                stream,
                new XmlReaderSettings
                {
                    DtdProcessing = DtdProcessing.Prohibit,
                    XmlResolver = null
                });
            var document = XDocument.Load(reader);
            XNamespace soap = SoapEnvelopeNamespace;
            XNamespace page = PageNamespace;
            if (document.Descendants(soap + "Fault").Any())
            {
                return Receipt(
                    NavisionPalletOutputDeliveryOutcome.UnknownResult,
                    status,
                    "SoapFault");
            }

            var output = document
                .Descendants(page + "Create_Result")
                .Elements(page + "WS_CPP_SalidasFabrica")
                .SingleOrDefault();
            if (output is null
                || !TryReadPositiveId(output, page, out var id)
                || !MatchesString(output, page, "Orden", job.OrderNumber)
                || !MatchesString(output, page, "Producto", job.ProductNumber)
                || !MatchesQuantity(output, page, job.GoodQuantity)
                || !MatchesString(output, page, "Tipo", "Salida"))
            {
                return Receipt(NavisionPalletOutputDeliveryOutcome.UnknownResult, status);
            }

            var externalIdentifier = id.ToString(CultureInfo.InvariantCulture);
            var state = output.Element(page + "Estado")?.Value;
            return state switch
            {
                "Registrado" => Receipt(
                    NavisionPalletOutputDeliveryOutcome.Confirmed,
                    status,
                    externalIdentifier: externalIdentifier),
                "Error" => Receipt(
                    NavisionPalletOutputDeliveryOutcome.PermanentFailure,
                    status,
                    externalIdentifier: externalIdentifier),
                _ => Receipt(
                    NavisionPalletOutputDeliveryOutcome.UnknownResult,
                    status,
                    externalIdentifier: externalIdentifier)
            };
        }
        catch (Exception exception)
            when (exception is XmlException or InvalidOperationException)
        {
            return Receipt(
                NavisionPalletOutputDeliveryOutcome.UnknownResult,
                status,
                exception.GetType().Name);
        }
    }

    private static bool TryReadPositiveId(
        XElement output,
        XNamespace page,
        out int id) =>
        int.TryParse(
            output.Element(page + "Id")?.Value,
            NumberStyles.None,
            CultureInfo.InvariantCulture,
            out id)
        && id > 0;

    private static bool MatchesString(
        XElement output,
        XNamespace page,
        string name,
        string expected) =>
        string.Equals(
            output.Element(page + name)?.Value,
            expected,
            StringComparison.Ordinal);

    private static bool MatchesQuantity(
        XElement output,
        XNamespace page,
        int expected) =>
        decimal.TryParse(
            output.Element(page + "Cantidad_salida")?.Value,
            NumberStyles.Number,
            CultureInfo.InvariantCulture,
            out var quantity)
        && quantity == expected;

    private static NavisionPalletOutputReceipt Receipt(
        NavisionPalletOutputDeliveryOutcome outcome,
        int? status,
        string? exception = null,
        string? externalIdentifier = null) =>
        new(
            outcome,
            externalIdentifier,
            status,
            JsonSerializer.Serialize(new
            {
                adapter = nameof(NavisionSoapPalletOutputSender),
                outcome = outcome.ToString(),
                httpStatus = status,
                exception
            }));
}
