using System.Net;
using System.Text;
using Ebir.Mes.Integrations.Navision;
using Xunit;

namespace Ebir.Mes.Integrations.Tests.Replenishment;

public sealed class NavisionSoapMaterialRequestStatusReaderTests
{
    [Fact]
    public async Task ReadAsync_ParsesPublishedNavCodeunitContract()
    {
        var handler = new Handler();
        var reader = new NavisionSoapMaterialRequestStatusReader(
            new HttpClient(handler),
            new NavisionOptions(new Uri("http://navision2.ebir.local:7147/EbirTest/WS/"),
                "EBIR", TimeSpan.FromSeconds(5)));
        var correlation = Guid.Parse("11111111-2222-4333-8444-555555555555");

        var status = await reader.ReadAsync(correlation, CancellationToken.None);

        Assert.NotNull(status);
        Assert.Equal(26932, status.RequestId);
        Assert.Equal(2, status.PickingStatusCode);
        Assert.Equal("Sin Registrar", status.PickingStatusText);
        Assert.Equal("APU21-1459", status.PickingNumber);
        Assert.Contains("<correlacionMES>11111111-2222-4333-8444-555555555555</correlacionMES>",
            handler.Body);
    }

    private sealed class Handler : HttpMessageHandler
    {
        public string Body { get; private set; } = string.Empty;

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Body = await request.Content!.ReadAsStringAsync(cancellationToken);
            const string response = """
                <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
                  <s:Body>
                    <ConsultarSolicitudMaterialMES_Result xmlns="urn:microsoft-dynamics-schemas/codeunit/WS_CPP_ControlPlanta">
                      <return_value>true</return_value>
                      <solicitudId>26932</solicitudId>
                      <estadoPickingCodigo>2</estadoPickingCodigo>
                      <estadoPickingTexto>Sin Registrar</estadoPickingTexto>
                      <numeroPicking>APU21-1459</numeroPicking>
                      <fechaRegistroPicking>1753-01-01T00:00:00Z</fechaRegistroPicking>
                      <errorPicking></errorPicking>
                    </ConsultarSolicitudMaterialMES_Result>
                  </s:Body>
                </s:Envelope>
                """;
            return new HttpResponseMessage(HttpStatusCode.OK)
            { Content = new StringContent(response, Encoding.UTF8, "text/xml") };
        }
    }
}
