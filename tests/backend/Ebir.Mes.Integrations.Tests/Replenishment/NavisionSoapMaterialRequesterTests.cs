using System.Net;
using System.Text;
using Ebir.Mes.Integrations.Navision;
using Xunit;

namespace Ebir.Mes.Integrations.Tests.Replenishment;

public sealed class NavisionSoapMaterialRequesterTests
{
    [Fact]
    public async Task RequestAsync_SendsSafeTestContractAndReturnsNavId()
    {
        var handler = new Handler();
        var requester = new NavisionSoapMaterialRequester(new HttpClient(handler),
            new NavisionOptions(new Uri("http://navision2.ebir.local:7147/EbirTest/WS/"),
                "EBIR", TimeSpan.FromSeconds(5)));
        var correlation = Guid.Parse("11111111-2222-4333-8444-555555555555");

        var id = await requester.RequestAsync(
            "FL26-00026", "27920", 1, correlation, CancellationToken.None);

        Assert.Equal(26932, id);
        Assert.Equal(
            "http://navision2.ebir.local:7147/EbirTest/WS/EBIR/Codeunit/WS_CPP_ControlPlanta",
            handler.Uri!.AbsoluteUri);
        Assert.Contains("<ordenProduccion>FL26-00026</ordenProduccion>", handler.Body);
        Assert.Contains("<idProd>27920</idProd>", handler.Body);
        Assert.Contains("<correlacionMES>11111111-2222-4333-8444-555555555555</correlacionMES>",
            handler.Body);
    }

    private sealed class Handler : HttpMessageHandler
    {
        public Uri? Uri { get; private set; }
        public string Body { get; private set; } = string.Empty;

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Uri = request.RequestUri;
            Body = await request.Content!.ReadAsStringAsync(cancellationToken);
            const string response = """
                <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
                  <s:Body>
                    <SolicitarMaterialMES_Result xmlns="urn:microsoft-dynamics-schemas/codeunit/WS_CPP_ControlPlanta">true</SolicitarMaterialMES_Result>
                    <solicitudId xmlns="urn:microsoft-dynamics-schemas/codeunit/WS_CPP_ControlPlanta">26932</solicitudId>
                  </s:Body>
                </s:Envelope>
                """;
            return new HttpResponseMessage(HttpStatusCode.OK)
            { Content = new StringContent(response, Encoding.UTF8, "text/xml") };
        }
    }
}
