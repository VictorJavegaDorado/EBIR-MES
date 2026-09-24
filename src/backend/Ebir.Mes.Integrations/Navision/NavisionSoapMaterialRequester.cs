using System.Globalization;
using System.Net;
using System.Text;
using System.Xml;
using System.Xml.Linq;
using Ebir.Mes.Application.Replenishment;

namespace Ebir.Mes.Integrations.Navision;

public sealed class NavisionSoapMaterialRequester(HttpClient httpClient, NavisionOptions options)
    : INavisionMaterialRequester
{
    private const string SoapNamespace = "http://schemas.xmlsoap.org/soap/envelope/";
    private const string CodeunitNamespace =
        "urn:microsoft-dynamics-schemas/codeunit/WS_CPP_ControlPlanta";
    private const string Operation = "SolicitarMaterialMES";

    public async Task<int> RequestAsync(string orderNumber, string componentCode,
        int quantity, Guid correlationId, CancellationToken cancellationToken)
    {
        for (var attempt = 1; attempt <= 2; attempt++)
        {
            using var request = CreateRequest(orderNumber, componentCode, quantity, correlationId);
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(options.RequestTimeout);
            try
            {
                using var response = await httpClient.SendAsync(
                    request, HttpCompletionOption.ResponseHeadersRead, timeout.Token);
                var body = await response.Content.ReadAsStringAsync(timeout.Token);
                if (response.IsSuccessStatusCode)
                    return ParseResponse(body);
                if (attempt < 2 && (response.StatusCode is HttpStatusCode.RequestTimeout
                    or HttpStatusCode.TooManyRequests || (int)response.StatusCode >= 500))
                    continue;
                throw new MaterialRequestUnavailableException(
                    "NAV ha rechazado la solicitud de material.");
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            { throw; }
            catch (Exception exception) when (attempt < 2
                && exception is HttpRequestException or OperationCanceledException)
            { }
            catch (MaterialRequestUnavailableException) { throw; }
            catch (Exception exception) when (exception is HttpRequestException or OperationCanceledException)
            {
                throw new MaterialRequestUnavailableException(
                    "NAV no está disponible para solicitar material.", exception);
            }
        }
        throw new MaterialRequestUnavailableException("NAV no está disponible.");
    }

    private HttpRequestMessage CreateRequest(string orderNumber, string componentCode,
        int quantity, Guid correlationId)
    {
        XNamespace soap = SoapNamespace;
        XNamespace codeunit = CodeunitNamespace;
        var document = new XDocument(new XElement(soap + "Envelope",
            new XElement(soap + "Body", new XElement(codeunit + Operation,
                new XElement(codeunit + "ordenProduccion", orderNumber),
                new XElement(codeunit + "idProd", componentCode),
                new XElement(codeunit + "cantidad", quantity.ToString(CultureInfo.InvariantCulture)),
                new XElement(codeunit + "correlacionMES", correlationId.ToString("D")),
                new XElement(codeunit + "solicitudId", "0")))));
        var endpoint = new Uri(options.ServiceRoot,
            $"{Uri.EscapeDataString(options.Company)}/Codeunit/WS_CPP_ControlPlanta");
        var request = new HttpRequestMessage(HttpMethod.Post, endpoint)
        {
            Content = new StringContent(document.ToString(SaveOptions.DisableFormatting),
                Encoding.UTF8, "text/xml")
        };
        request.Headers.TryAddWithoutValidation("SOAPAction", CodeunitNamespace + ":" + Operation);
        return request;
    }

    private static int ParseResponse(string body)
    {
        try
        {
            using var text = new StringReader(body);
            using var reader = XmlReader.Create(text, new XmlReaderSettings
            { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null });
            var document = XDocument.Load(reader);
            XNamespace soap = SoapNamespace;
            XNamespace codeunit = CodeunitNamespace;
            if (document.Descendants(soap + "Fault").Any())
                throw new MaterialRequestUnavailableException("NAV ha rechazado la solicitud de material.");
            var succeeded = document.Descendants(codeunit + Operation + "_Result").SingleOrDefault()?.Value;
            var id = document.Descendants(codeunit + "solicitudId").SingleOrDefault()?.Value;
            if (!bool.TryParse(succeeded, out var ok) || !ok || !int.TryParse(id, out var requestId)
                || requestId <= 0)
                throw new MaterialRequestUnavailableException("NAV devolvió una respuesta incompleta.");
            return requestId;
        }
        catch (MaterialRequestUnavailableException) { throw; }
        catch (Exception exception) when (exception is XmlException or InvalidOperationException)
        {
            throw new MaterialRequestUnavailableException("NAV devolvió una respuesta no válida.", exception);
        }
    }
}
