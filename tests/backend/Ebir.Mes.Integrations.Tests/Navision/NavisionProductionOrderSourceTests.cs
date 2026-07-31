using System.Net;
using System.Text;
using Ebir.Mes.Application.ProductionOrders;
using Ebir.Mes.Integrations.Navision;
using Xunit;

namespace Ebir.Mes.Integrations.Tests.Navision;

public sealed class NavisionProductionOrderSourceTests
{
    [Fact]
    public async Task ReadAsync_maps_records_and_limits_released_query()
    {
        string? requestBody = null;
        Uri? requestUri = null;
        string? soapAction = null;
        var handler = new StubHandler(async request =>
        {
            requestUri = request.RequestUri;
            soapAction = request.Headers.GetValues("SOAPAction").Single();
            requestBody = await request.Content!.ReadAsStringAsync();
            return SoapResponse(ProductionOrdersResponse);
        });
        var source = CreateSource(handler);

        var result = await source.ReadAsync(
            ProductionOrderStatus.Released,
            2,
            CancellationToken.None);

        var order = Assert.Single(result);
        Assert.Equal("OF26-00042", order.OrderNumber);
        Assert.Equal(ProductionOrderStatus.Released, order.Status);
        Assert.Equal("PRODUCTO PILOTO", order.Description);
        Assert.Equal("ITEM-01", order.ProductNumber);
        Assert.Equal("RUTA-01", order.RoutingNumber);
        Assert.Equal(125.5m, order.Quantity);
        Assert.Equal("FABRICA", order.LocationCode);
        Assert.Equal(new DateOnly(2026, 7, 31), order.StartingDate);
        Assert.Equal(new DateOnly(2026, 8, 1), order.EndingDate);
        Assert.Equal(new DateOnly(2026, 8, 2), order.DueDate);
        Assert.Equal(
            new Uri("http://nav.test/instance/WS/EBIR/Page/WS_CPP_ProdOrderList"),
            requestUri);
        Assert.Equal(
            "urn:microsoft-dynamics-schemas/page/ws_cpp_prodorderlist:ReadMultiple",
            soapAction);
        Assert.Contains("<Field>Status</Field>", requestBody);
        Assert.Contains("<Criteria>Released</Criteria>", requestBody);
        Assert.Contains("<setSize>2</setSize>", requestBody);
    }

    [Fact]
    public async Task ReadAsync_retries_transient_read_failure()
    {
        var responseNumber = 0;
        var handler = new StubHandler(_ =>
        {
            responseNumber++;
            var response = responseNumber == 1
                ? new HttpResponseMessage(HttpStatusCode.ServiceUnavailable)
                : SoapResponse(EmptyResponse);
            return Task.FromResult(response);
        });

        var result = await CreateSource(handler).ReadAsync(
            ProductionOrderStatus.Released,
            10,
            CancellationToken.None);

        Assert.Empty(result);
        Assert.Equal(2, handler.CallCount);
    }

    [Fact]
    public async Task ReadAsync_does_not_retry_non_transient_fault()
    {
        var handler = new StubHandler(_ =>
            Task.FromResult(new HttpResponseMessage(HttpStatusCode.BadRequest)
            {
                Content = new StringContent(SoapFault, Encoding.UTF8, "text/xml")
            }));

        var exception =
            await Assert.ThrowsAsync<ProductionOrderSourceUnavailableException>(
                () => CreateSource(handler).ReadAsync(
                    ProductionOrderStatus.Released,
                    10,
                    CancellationToken.None));

        Assert.Contains("soap:Client", exception.Message);
        Assert.Equal(1, handler.CallCount);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(101)]
    public async Task ReadAsync_rejects_unsafe_page_size(int maximumRecords)
    {
        var handler = new StubHandler(_ =>
            Task.FromResult(SoapResponse(EmptyResponse)));

        await Assert.ThrowsAsync<ArgumentOutOfRangeException>(
            () => CreateSource(handler).ReadAsync(
                ProductionOrderStatus.Released,
                maximumRecords,
                CancellationToken.None));

        Assert.Equal(0, handler.CallCount);
    }

    [Fact]
    public async Task ReadAsync_rejects_malformed_soap()
    {
        var handler = new StubHandler(_ =>
            Task.FromResult(SoapResponse("<not-xml")));

        var exception =
            await Assert.ThrowsAsync<ProductionOrderSourceUnavailableException>(
                () => CreateSource(handler).ReadAsync(
                    ProductionOrderStatus.Released,
                    10,
                    CancellationToken.None));

        Assert.Equal(
            "NAV returned an invalid production order response.",
            exception.Message);
    }

    private static NavisionProductionOrderSource CreateSource(
        HttpMessageHandler handler)
    {
        var options = new NavisionOptions(
            new Uri("http://nav.test/instance/WS"),
            "EBIR",
            TimeSpan.FromSeconds(5));
        return new NavisionProductionOrderSource(
            new HttpClient(handler),
            options);
    }

    private static HttpResponseMessage SoapResponse(string body) =>
        new(HttpStatusCode.OK)
        {
            Content = new StringContent(body, Encoding.UTF8, "text/xml")
        };

    private sealed class StubHandler(
        Func<HttpRequestMessage, Task<HttpResponseMessage>> responseFactory)
        : HttpMessageHandler
    {
        public int CallCount { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            CallCount++;
            return responseFactory(request);
        }
    }

    private const string ProductionOrdersResponse = """
        <?xml version="1.0" encoding="utf-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <ReadMultiple_Result xmlns="urn:microsoft-dynamics-schemas/page/ws_cpp_prodorderlist">
              <ReadMultiple_Result>
                <WS_CPP_ProdOrderList>
                  <Key>TEST-KEY</Key>
                  <No>OF26-00042</No>
                  <Description>PRODUCTO PILOTO</Description>
                  <Source_No>ITEM-01</Source_No>
                  <Routing_No>RUTA-01</Routing_No>
                  <Quantity>125.5</Quantity>
                  <Location_Code>FABRICA</Location_Code>
                  <Starting_Date>2026-07-31</Starting_Date>
                  <Ending_Date>2026-08-01</Ending_Date>
                  <Due_Date>2026-08-02</Due_Date>
                  <Status>Released</Status>
                </WS_CPP_ProdOrderList>
              </ReadMultiple_Result>
            </ReadMultiple_Result>
          </soap:Body>
        </soap:Envelope>
        """;

    private const string EmptyResponse = """
        <?xml version="1.0" encoding="utf-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <ReadMultiple_Result xmlns="urn:microsoft-dynamics-schemas/page/ws_cpp_prodorderlist">
              <ReadMultiple_Result />
            </ReadMultiple_Result>
          </soap:Body>
        </soap:Envelope>
        """;

    private const string SoapFault = """
        <?xml version="1.0" encoding="utf-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <soap:Fault>
              <faultcode>soap:Client</faultcode>
              <faultstring>synthetic test fault</faultstring>
            </soap:Fault>
          </soap:Body>
        </soap:Envelope>
        """;
}
