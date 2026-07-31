using System.Net;
using System.Text;
using Ebir.Mes.Application.ProductionOrders;
using Ebir.Mes.Integrations.Navision;
using Xunit;

namespace Ebir.Mes.Integrations.Tests.Navision;

public sealed class NavisionProductionOrderSourceTests
{
    [Fact]
    public async Task ReadOrderAsync_uses_exact_order_filter()
    {
        string? requestBody = null;
        var handler = new StubHandler(async request =>
        {
            requestBody = await request.Content!.ReadAsStringAsync();
            return SoapResponse(ProductionOrdersResponse);
        });

        var result = await CreateSource(handler).ReadOrderAsync(
            ProductionOrderStatus.Released,
            " of26-00042 ",
            CancellationToken.None);

        Assert.Equal("OF26-00042", result!.OrderNumber);
        Assert.Contains("<Field>Status</Field>", requestBody);
        Assert.Contains("<Criteria>Released</Criteria>", requestBody);
        Assert.Contains("<Field>No</Field>", requestBody);
        Assert.Contains("<Criteria>OF26-00042</Criteria>", requestBody);
        Assert.Contains("<setSize>2</setSize>", requestBody);
    }

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
    public async Task ReadLinesAsync_maps_line_and_uses_exact_order_filter()
    {
        string? requestBody = null;
        Uri? requestUri = null;
        var handler = new StubHandler(async request =>
        {
            requestUri = request.RequestUri;
            requestBody = await request.Content!.ReadAsStringAsync();
            return SoapResponse(ProductionOrderLinesResponse);
        });

        var result = await CreateSource(handler).ReadLinesAsync(
            ProductionOrderStatus.Released,
            " of26-00042 ",
            10,
            CancellationToken.None);

        var line = Assert.Single(result);
        Assert.Equal("OF26-00042", line.OrderNumber);
        Assert.Equal(ProductionOrderStatus.Released, line.Status);
        Assert.Equal("ITEM-01", line.ProductNumber);
        Assert.Equal("AZUL", line.VariantCode);
        Assert.Equal("PRODUCTO PILOTO", line.Description);
        Assert.Equal("FABRICA", line.LocationCode);
        Assert.Equal(125.5m, line.Quantity);
        Assert.Equal(25.5m, line.FinishedQuantity);
        Assert.Equal(100m, line.RemainingQuantity);
        Assert.Equal(1.25m, line.ScrapPercent);
        Assert.Equal(new DateOnly(2026, 8, 2), line.DueDate);
        Assert.Equal(new DateOnly(2026, 7, 31), line.StartingDate);
        Assert.Equal(new DateOnly(2026, 8, 1), line.EndingDate);
        Assert.Equal("BOM-01", line.ProductionBomNumber);
        Assert.Equal(
            new Uri(
                "http://nav.test/instance/WS/EBIR/Page/WS_CPP_ProdOrderLineList"),
            requestUri);
        Assert.Contains("<Field>Status</Field>", requestBody);
        Assert.Contains("<Criteria>Released</Criteria>", requestBody);
        Assert.Contains("<Field>Prod_Order_No</Field>", requestBody);
        Assert.Contains("<Criteria>OF26-00042</Criteria>", requestBody);
    }

    [Fact]
    public async Task ReadRoutingAsync_maps_route_and_requires_exact_order()
    {
        string? requestBody = null;
        string? soapAction = null;
        var handler = new StubHandler(async request =>
        {
            requestBody = await request.Content!.ReadAsStringAsync();
            soapAction = request.Headers.GetValues("SOAPAction").Single();
            return SoapResponse(ProductionOrderRoutingResponse);
        });

        var result = await CreateSource(handler).ReadRoutingAsync(
            "of26-00042",
            20,
            CancellationToken.None);

        var step = Assert.Single(result);
        Assert.Equal("OF26-00042", step.OrderNumber);
        Assert.Equal(10000, step.RoutingReferenceNumber);
        Assert.Equal("RUTA-01", step.RoutingNumber);
        Assert.Equal("010", step.OperationNumber);
        Assert.Equal("005", step.PreviousOperationNumber);
        Assert.Equal("020", step.NextOperationNumber);
        Assert.Equal(ProductionRoutingStepType.WorkCenter, step.Type);
        Assert.Equal("CT-01", step.CapacityNumber);
        Assert.Equal("MEZCLADO", step.Description);
        Assert.Equal(new DateTime(2026, 7, 31, 8, 0, 0), step.StartingAt);
        Assert.Equal(new DateTime(2026, 7, 31, 10, 0, 0), step.EndingAt);
        Assert.Equal(0.5m, step.SetupTime);
        Assert.Equal(2.25m, step.RunTime);
        Assert.Equal(0.1m, step.WaitTime);
        Assert.Equal(0.2m, step.MoveTime);
        Assert.Equal(0.3m, step.FixedScrapQuantity);
        Assert.Equal("RL-010", step.RoutingLinkCode);
        Assert.Equal(1.5m, step.ScrapFactorPercent);
        Assert.Equal(ProductionRoutingStatus.InProgress, step.Status);
        Assert.Equal("FABRICA", step.LocationCode);
        Assert.True(step.IsSigning);
        Assert.Equal(
            "urn:microsoft-dynamics-schemas/page/ws_cpp_rutaordenproduccion:ReadMultiple",
            soapAction);
        Assert.Contains("<Criteria>OF26-00042</Criteria>", requestBody);
        Assert.DoesNotContain("<Field>Status</Field>", requestBody);
    }

    [Fact]
    public async Task ReadComponentsAsync_maps_component_linkage_and_quantities()
    {
        string? requestBody = null;
        var handler = new StubHandler(async request =>
        {
            requestBody = await request.Content!.ReadAsStringAsync();
            return SoapResponse(ProductionOrderComponentsResponse);
        });

        var result = await CreateSource(handler).ReadComponentsAsync(
            ProductionOrderStatus.Released,
            "OF26-00042",
            50,
            CancellationToken.None);

        var component = Assert.Single(result);
        Assert.Equal("OF26-00042", component.OrderNumber);
        Assert.Equal(10000, component.ProductionOrderLineNumber);
        Assert.Equal(20000, component.LineNumber);
        Assert.Equal(ProductionOrderStatus.Released, component.Status);
        Assert.Equal("MAT-01", component.ItemNumber);
        Assert.Equal("V1", component.VariantCode);
        Assert.Equal("MATERIA PRIMA", component.Description);
        Assert.Equal(2.5m, component.QuantityPer);
        Assert.Equal(312.5m, component.ExpectedQuantity);
        Assert.Equal(250m, component.RemainingQuantity);
        Assert.Equal(62.5m, component.ActualConsumptionQuantity);
        Assert.Equal("KG", component.UnitOfMeasureCode);
        Assert.Equal(
            ProductionComponentFlushingMethod.PickAndForward,
            component.FlushingMethod);
        Assert.Equal("RL-010", component.RoutingLinkCode);
        Assert.Equal("010", component.OperationCode);
        Assert.Equal("FABRICA", component.LocationCode);
        Assert.Equal("MP-01", component.BinCode);
        Assert.Equal(70m, component.QuantityPicked);
        Assert.True(component.SubstitutionAvailable);
        Assert.Contains("<Criteria>Released</Criteria>", requestBody);
        Assert.Contains("<Criteria>OF26-00042</Criteria>", requestBody);
    }

    [Theory]
    [InlineData("")]
    [InlineData("OF26-00042|OF26-00043")]
    [InlineData("OF26-00042..OF26-9")]
    [InlineData("123456789012345678901")]
    public async Task Detail_reads_reject_non_exact_order_filter(
        string orderNumber)
    {
        var handler = new StubHandler(_ =>
            Task.FromResult(SoapResponse(EmptyResponse)));

        await Assert.ThrowsAnyAsync<ArgumentException>(
            () => CreateSource(handler).ReadRoutingAsync(
                orderNumber,
                10,
                CancellationToken.None));

        Assert.Equal(0, handler.CallCount);
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

    private const string ProductionOrderLinesResponse = """
        <?xml version="1.0" encoding="utf-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <ReadMultiple_Result xmlns="urn:microsoft-dynamics-schemas/page/ws_cpp_prodorderlinelist">
              <ReadMultiple_Result>
                <WS_CPP_ProdOrderLineList>
                  <Key>LINE-KEY</Key>
                  <Status>Released</Status>
                  <Prod_Order_No>OF26-00042</Prod_Order_No>
                  <Item_No>ITEM-01</Item_No>
                  <Variant_Code>AZUL</Variant_Code>
                  <Description>PRODUCTO PILOTO</Description>
                  <Location_Code>FABRICA</Location_Code>
                  <Quantity>125.5</Quantity>
                  <Finished_Quantity>25.5</Finished_Quantity>
                  <Remaining_Quantity>100</Remaining_Quantity>
                  <Scrap_Percent>1.25</Scrap_Percent>
                  <Due_Date>2026-08-02</Due_Date>
                  <Starting_Date>2026-07-31</Starting_Date>
                  <Ending_Date>2026-08-01</Ending_Date>
                  <Production_BOM_No>BOM-01</Production_BOM_No>
                </WS_CPP_ProdOrderLineList>
              </ReadMultiple_Result>
            </ReadMultiple_Result>
          </soap:Body>
        </soap:Envelope>
        """;

    private const string ProductionOrderRoutingResponse = """
        <?xml version="1.0" encoding="utf-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <ReadMultiple_Result xmlns="urn:microsoft-dynamics-schemas/page/ws_cpp_rutaordenproduccion">
              <ReadMultiple_Result>
                <WS_CPP_RutaOrdenProduccion>
                  <Key>ROUTE-KEY</Key>
                  <Prod_Order_No>OF26-00042</Prod_Order_No>
                  <Operation_No>010</Operation_No>
                  <Previous_Operation_No>005</Previous_Operation_No>
                  <Next_Operation_No>020</Next_Operation_No>
                  <Type>Work_Center</Type>
                  <No>CT-01</No>
                  <Description>MEZCLADO</Description>
                  <Starting_Date_Time>2026-07-31T08:00:00</Starting_Date_Time>
                  <Ending_Date_Time>2026-07-31T10:00:00</Ending_Date_Time>
                  <Setup_Time>0.5</Setup_Time>
                  <Run_Time>2.25</Run_Time>
                  <Wait_Time>0.1</Wait_Time>
                  <Move_Time>0.2</Move_Time>
                  <Fixed_Scrap_Quantity>0.3</Fixed_Scrap_Quantity>
                  <Routing_Link_Code>RL-010</Routing_Link_Code>
                  <Scrap_Factor_Percent>1.5</Scrap_Factor_Percent>
                  <Routing_Status>In_Progress</Routing_Status>
                  <Location_Code>FABRICA</Location_Code>
                  <Routing_No>RUTA-01</Routing_No>
                  <Routing_Reference_No>10000</Routing_Reference_No>
                  <IsSigning>true</IsSigning>
                </WS_CPP_RutaOrdenProduccion>
              </ReadMultiple_Result>
            </ReadMultiple_Result>
          </soap:Body>
        </soap:Envelope>
        """;

    private const string ProductionOrderComponentsResponse = """
        <?xml version="1.0" encoding="utf-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <ReadMultiple_Result xmlns="urn:microsoft-dynamics-schemas/page/ws_cpp_componentes">
              <ReadMultiple_Result>
                <WS_CPP_Componentes>
                  <Key>COMPONENT-KEY</Key>
                  <Item_No>MAT-01</Item_No>
                  <Variant_Code>V1</Variant_Code>
                  <Description>MATERIA PRIMA</Description>
                  <Quantity_per>2.5</Quantity_per>
                  <Unit_of_Measure_Code>KG</Unit_of_Measure_Code>
                  <Flushing_Method>Pick__x002B__Forward</Flushing_Method>
                  <Expected_Quantity>312.5</Expected_Quantity>
                  <Remaining_Quantity>250</Remaining_Quantity>
                  <Routing_Link_Code>RL-010</Routing_Link_Code>
                  <Location_Code>FABRICA</Location_Code>
                  <Bin_Code>MP-01</Bin_Code>
                  <Qty_Picked>70</Qty_Picked>
                  <Substitution_Available>true</Substitution_Available>
                  <Status>Released</Status>
                  <Prod_Order_No>OF26-00042</Prod_Order_No>
                  <Prod_Order_Line_No>10000</Prod_Order_Line_No>
                  <Line_No>20000</Line_No>
                  <Act_Consumption_Qty>62.5</Act_Consumption_Qty>
                  <Cod_Operacion>010</Cod_Operacion>
                </WS_CPP_Componentes>
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
