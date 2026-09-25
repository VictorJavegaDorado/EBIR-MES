using System.Globalization;
using System.Net;
using System.Text;
using System.Xml;
using System.Xml.Linq;
using Ebir.Mes.Application.Replenishment;

namespace Ebir.Mes.Integrations.Navision;

public sealed class DisabledNavisionMaterialRequestStatusReader
    : INavisionMaterialRequestStatusReader
{
    public Task<NavMaterialRequestStatus?> ReadAsync(
        Guid correlationId,
        CancellationToken cancellationToken) =>
        throw new MaterialRequestUnavailableException(
            "El seguimiento NAV de material está desactivado.");
}

public sealed class NavisionSoapMaterialRequestStatusReader(
    HttpClient httpClient,
    NavisionOptions options) : INavisionMaterialRequestStatusReader
{
    private const string SoapNamespace = "http://schemas.xmlsoap.org/soap/envelope/";
    private const string CodeunitNamespace =
        "urn:microsoft-dynamics-schemas/codeunit/WS_CPP_ControlPlanta";
    private const string Operation = "ConsultarSolicitudMaterialMES";

    public async Task<NavMaterialRequestStatus?> ReadAsync(
        Guid correlationId,
        CancellationToken cancellationToken)
    {
        for (var attempt = 1; attempt <= 2; attempt++)
        {
            using var request = CreateRequest(correlationId);
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
                    "NAV ha rechazado la consulta de material.");
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            { throw; }
            catch (Exception exception) when (attempt < 2
                && exception is HttpRequestException or OperationCanceledException)
            { }
            catch (MaterialRequestUnavailableException) { throw; }
            catch (Exception exception)
                when (exception is HttpRequestException or OperationCanceledException)
            {
                throw new MaterialRequestUnavailableException(
                    "NAV no está disponible para consultar material.", exception);
            }
        }
        throw new MaterialRequestUnavailableException("NAV no está disponible.");
    }

    private HttpRequestMessage CreateRequest(Guid correlationId)
    {
        XNamespace soap = SoapNamespace;
        XNamespace codeunit = CodeunitNamespace;
        var document = new XDocument(new XElement(soap + "Envelope",
            new XElement(soap + "Body", new XElement(codeunit + Operation,
                new XElement(codeunit + "correlacionMES", correlationId.ToString("D")),
                new XElement(codeunit + "solicitudId", "0"),
                new XElement(codeunit + "estadoPickingCodigo", "0"),
                new XElement(codeunit + "estadoPickingTexto", string.Empty),
                new XElement(codeunit + "numeroPicking", string.Empty),
                new XElement(codeunit + "fechaRegistroPicking", "1753-01-01T00:00:00Z"),
                new XElement(codeunit + "errorPicking", string.Empty)))));
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

    private static NavMaterialRequestStatus? ParseResponse(string body)
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
                throw new MaterialRequestUnavailableException(
                    "NAV ha rechazado la consulta de material.");
            var found = Value(document, codeunit, "return_value");
            if (!bool.TryParse(found, out var exists))
                throw new MaterialRequestUnavailableException(
                    "NAV devolvió una respuesta de seguimiento incompleta.");
            if (!exists)
                return null;

            if (!int.TryParse(Value(document, codeunit, "solicitudId"), out var requestId)
                || requestId <= 0
                || !int.TryParse(Value(document, codeunit, "estadoPickingCodigo"),
                    out var statusCode))
                throw new MaterialRequestUnavailableException(
                    "NAV devolvió una respuesta de seguimiento incompleta.");

            var registeredText = Value(document, codeunit, "fechaRegistroPicking");
            DateTime? registeredAt = null;
            if (DateTime.TryParse(registeredText, CultureInfo.InvariantCulture,
                    DateTimeStyles.RoundtripKind, out var parsedDate)
                && parsedDate.Year > 1753)
                registeredAt = parsedDate;

            return new(
                requestId,
                statusCode,
                Value(document, codeunit, "estadoPickingTexto") ?? string.Empty,
                EmptyToNull(Value(document, codeunit, "numeroPicking")),
                registeredAt,
                EmptyToNull(Value(document, codeunit, "errorPicking")));
        }
        catch (MaterialRequestUnavailableException) { throw; }
        catch (Exception exception)
            when (exception is XmlException or InvalidOperationException)
        {
            throw new MaterialRequestUnavailableException(
                "NAV devolvió una respuesta de seguimiento no válida.", exception);
        }
    }

    private static string? Value(XDocument document, XNamespace ns, string name) =>
        document.Descendants(ns + name).SingleOrDefault()?.Value;

    private static string? EmptyToNull(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
