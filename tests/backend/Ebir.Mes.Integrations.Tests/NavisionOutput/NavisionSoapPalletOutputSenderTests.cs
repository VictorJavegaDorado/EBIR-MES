using System.Net;
using System.Text;
using System.Xml.Linq;
using Ebir.Mes.Application.NavisionOutput;
using Ebir.Mes.Integrations.NavisionOutput;
using Xunit;

namespace Ebir.Mes.Integrations.Tests.NavisionOutput;

public sealed class NavisionSoapPalletOutputSenderTests
{
    private const string PageNamespace =
        "urn:microsoft-dynamics-schemas/page/ws_cpp_salidasfabrica";
    private const string SoapNamespace =
        "http://schemas.xmlsoap.org/soap/envelope/";

    [Fact]
    public async Task SendAsync_creates_exact_output_and_maps_created_entity()
    {
        HttpRequestMessage? captured = null;
        string? requestXml = null;
        var handler = new StubHandler(async (request, cancellationToken) =>
        {
            captured = request;
            requestXml = await request.Content!.ReadAsStringAsync(cancellationToken);
            return Soap(
                Output(
                    id: 321,
                    order: "FL-TEST",
                    product: "ITEM-TEST",
                    quantity: "20",
                    type: "Salida",
                    state: "Registrado"));
        });
        var sender = CreateSender(handler);

        var result = await sender.SendAsync(Job, CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.Confirmed, result.Outcome);
        Assert.Equal("321", result.ExternalIdentifier);
        Assert.Equal(HttpMethod.Post, captured!.Method);
        Assert.Equal(Endpoint, captured.RequestUri);
        Assert.Equal("text/xml", captured.Content!.Headers.ContentType!.MediaType);
        Assert.Equal(
            PageNamespace + ":Create",
            captured.Headers.GetValues("SOAPAction").Single());

        var document = XDocument.Parse(requestXml!);
        XNamespace page = PageNamespace;
        var create = document.Descendants(page + "Create").Single();
        var output = create.Element(page + "WS_CPP_SalidasFabrica")!;
        Assert.Equal("FL-TEST", output.Element(page + "Orden")!.Value);
        Assert.Equal("ITEM-TEST", output.Element(page + "Producto")!.Value);
        Assert.Equal("20", output.Element(page + "Cantidad_salida")!.Value);
        Assert.Equal("2026-08-06T10:30:00Z", output.Element(page + "fecha")!.Value);
        Assert.Equal("Salida", output.Element(page + "Tipo")!.Value);
        Assert.Null(output.Element(page + "Estado"));
        Assert.Null(output.Element(page + "Estado_Consumo"));
        Assert.Null(output.Element(page + "Key"));
        Assert.Null(output.Element(page + "Id"));
    }

    [Theory]
    [InlineData(HttpStatusCode.BadRequest,
        NavisionPalletOutputDeliveryOutcome.PermanentFailure)]
    [InlineData(HttpStatusCode.MethodNotAllowed,
        NavisionPalletOutputDeliveryOutcome.PermanentFailure)]
    [InlineData(HttpStatusCode.Unauthorized,
        NavisionPalletOutputDeliveryOutcome.PermanentFailure)]
    [InlineData(HttpStatusCode.RequestTimeout,
        NavisionPalletOutputDeliveryOutcome.UnknownResult)]
    [InlineData(HttpStatusCode.TooManyRequests,
        NavisionPalletOutputDeliveryOutcome.UnknownResult)]
    [InlineData(HttpStatusCode.InternalServerError,
        NavisionPalletOutputDeliveryOutcome.UnknownResult)]
    public async Task SendAsync_classifies_http_without_exposing_response(
        HttpStatusCode status,
        NavisionPalletOutputDeliveryOutcome expected)
    {
        var sender = CreateSender(new StubHandler((_, _) => Task.FromResult(
            new HttpResponseMessage(status)
            {
                Content = new StringContent("SENSITIVE NAV BODY")
            })));

        var result = await sender.SendAsync(Job, CancellationToken.None);

        Assert.Equal(expected, result.Outcome);
        Assert.DoesNotContain("SENSITIVE", result.TechnicalDataJson);
    }

    [Fact]
    public async Task SendAsync_marks_mismatched_success_as_unknown()
    {
        var sender = CreateSender(new StubHandler((_, _) => Task.FromResult(
            Soap(Output(
                321,
                "OTHER",
                "ITEM-TEST",
                "20",
                "Salida",
                "Pendiente")))));

        var result = await sender.SendAsync(Job, CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.UnknownResult, result.Outcome);
        Assert.Null(result.ExternalIdentifier);
    }

    [Theory]
    [InlineData("Pendiente", NavisionPalletOutputDeliveryOutcome.UnknownResult)]
    [InlineData("Error", NavisionPalletOutputDeliveryOutcome.PermanentFailure)]
    public async Task SendAsync_preserves_created_id_until_nav_registers_output(
        string state,
        NavisionPalletOutputDeliveryOutcome expected)
    {
        var sender = CreateSender(new StubHandler((_, _) => Task.FromResult(
            Soap(Output(
                321,
                "FL-TEST",
                "ITEM-TEST",
                "20.0",
                "Salida",
                state)))));

        var result = await sender.SendAsync(Job, CancellationToken.None);

        Assert.Equal(expected, result.Outcome);
        Assert.Equal("321", result.ExternalIdentifier);
    }

    [Fact]
    public async Task SendAsync_marks_soap_fault_as_unknown_without_exposing_fault()
    {
        var sender = CreateSender(new StubHandler((_, _) => Task.FromResult(
            SoapBody(
                """
                <s:Fault xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
                  <faultcode>s:Server</faultcode>
                  <faultstring>SENSITIVE NAV FAULT</faultstring>
                </s:Fault>
                """))));

        var result = await sender.SendAsync(Job, CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.UnknownResult, result.Outcome);
        Assert.DoesNotContain("SENSITIVE", result.TechnicalDataJson);
        Assert.Contains("SoapFault", result.TechnicalDataJson);
    }

    [Fact]
    public async Task SendAsync_marks_invalid_xml_as_unknown()
    {
        var sender = CreateSender(new StubHandler((_, _) => Task.FromResult(
            new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent("<invalid", Encoding.UTF8, "text/xml")
            })));

        var result = await sender.SendAsync(Job, CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.UnknownResult, result.Outcome);
        Assert.Contains("XmlException", result.TechnicalDataJson);
    }

    [Fact]
    public async Task SendAsync_marks_transport_failure_as_unknown()
    {
        var sender = CreateSender(new StubHandler((_, _) =>
            throw new HttpRequestException("Synthetic transport failure")));

        var result = await sender.SendAsync(Job, CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.UnknownResult, result.Outcome);
        Assert.DoesNotContain("Synthetic transport failure", result.TechnicalDataJson);
    }

    [Theory]
    [InlineData("http://external.example:7147/EbirTest/WS/EBIR/Page/WS_CPP_SalidasFabrica")]
    [InlineData("http://Navision.EBIR.LOCAL:7147/EbirTest/ODataV4/Company('EBIR')/WS_CPP_SalidasFabrica")]
    [InlineData("http://Navision.EBIR.LOCAL:7147/EbirTest/WS/OTHER/Page/WS_CPP_SalidasFabrica")]
    [InlineData("http://Navision.EBIR.LOCAL:7147/EbirTest/WS/EBIR/Page/WS_CPP_SalidasFabrica?x=1")]
    public void Options_rejects_endpoint_outside_exact_test_page(string endpoint)
    {
        Assert.Throws<ArgumentException>(() =>
            new NavisionPalletOutputOptions(
                new Uri(endpoint),
                TimeSpan.FromSeconds(10)));
    }

    private static NavisionSoapPalletOutputSender CreateSender(
        HttpMessageHandler handler) =>
        new(
            new HttpClient(handler),
            new NavisionPalletOutputOptions(Endpoint, TimeSpan.FromSeconds(10)));

    private static HttpResponseMessage Soap(string output) =>
        SoapBody(
            $$"""
            <Create_Result xmlns="{{PageNamespace}}">
              {{output}}
            </Create_Result>
            """);

    private static HttpResponseMessage SoapBody(string body) =>
        new(HttpStatusCode.OK)
        {
            Content = new StringContent(
                $$"""
                <s:Envelope xmlns:s="{{SoapNamespace}}">
                  <s:Body>{{body}}</s:Body>
                </s:Envelope>
                """,
                Encoding.UTF8,
                "text/xml")
        };

    private static string Output(
        int id,
        string order,
        string product,
        string quantity,
        string type,
        string state) =>
        $$"""
        <WS_CPP_SalidasFabrica xmlns="{{PageNamespace}}">
          <Id>{{id}}</Id>
          <Orden>{{order}}</Orden>
          <Producto>{{product}}</Producto>
          <Cantidad_salida>{{quantity}}</Cantidad_salida>
          <Estado>{{state}}</Estado>
          <Tipo>{{type}}</Tipo>
        </WS_CPP_SalidasFabrica>
        """;

    private static readonly Uri Endpoint = new(
        "http://Navision.EBIR.LOCAL:7147/EbirTest/WS/EBIR/Page/WS_CPP_SalidasFabrica");

    private static readonly NavisionPalletOutputJob Job = new(
        7,
        Guid.Parse("11111111-1111-1111-1111-111111111111"),
        "MES:PALET:synthetic",
        "FL-TEST",
        "ITEM-TEST",
        20,
        new DateTimeOffset(2026, 8, 6, 10, 30, 0, TimeSpan.Zero),
        1);

    private sealed class StubHandler(
        Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send)
        : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken) => send(request, cancellationToken);
    }
}
