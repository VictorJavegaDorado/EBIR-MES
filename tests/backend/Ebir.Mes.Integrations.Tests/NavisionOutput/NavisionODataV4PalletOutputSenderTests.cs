using System.Net;
using System.Text;
using System.Text.Json;
using Ebir.Mes.Application.NavisionOutput;
using Ebir.Mes.Integrations.NavisionOutput;
using Xunit;

namespace Ebir.Mes.Integrations.Tests.NavisionOutput;

public sealed class NavisionODataV4PalletOutputSenderTests
{
    [Fact]
    public async Task SendAsync_posts_exact_output_and_maps_created_entity()
    {
        HttpRequestMessage? captured = null;
        string? requestJson = null;
        var handler = new StubHandler(async (request, cancellationToken) =>
        {
            captured = request;
            requestJson = await request.Content!.ReadAsStringAsync(cancellationToken);
            return Json(HttpStatusCode.Created,
                """
                {
                  "Id": 321,
                  "Orden": "FL-TEST",
                  "Producto": "ITEM-TEST",
                  "Cantidad_salida": 20.0,
                  "Tipo": "Salida",
                  "Estado": "Registrado"
                }
                """);
        });
        var sender = CreateSender(handler);

        var result = await sender.SendAsync(Job, CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.Confirmed, result.Outcome);
        Assert.Equal("321", result.ExternalIdentifier);
        Assert.Equal(HttpMethod.Post, captured!.Method);
        Assert.Equal(Endpoint, captured.RequestUri);
        using var document = JsonDocument.Parse(requestJson!);
        var root = document.RootElement;
        Assert.Equal("FL-TEST", root.GetProperty("Orden").GetString());
        Assert.Equal("ITEM-TEST", root.GetProperty("Producto").GetString());
        Assert.Equal(20, root.GetProperty("Cantidad_salida").GetInt32());
        Assert.Equal("Salida", root.GetProperty("Tipo").GetString());
        Assert.False(root.TryGetProperty("Estado", out _));
        Assert.False(root.TryGetProperty("Estado_Consumo", out _));
        Assert.False(root.TryGetProperty("Key", out _));
        Assert.False(root.TryGetProperty("Id", out _));
    }

    [Theory]
    [InlineData(HttpStatusCode.BadRequest,
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
            Json(HttpStatusCode.Created,
                """{"Id":321,"Orden":"OTHER","Producto":"ITEM-TEST","Cantidad_salida":20,"Tipo":"Salida","Estado":"Pendiente"}"""))));

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
            Json(HttpStatusCode.Created,
                $$"""{"Id":321,"Orden":"FL-TEST","Producto":"ITEM-TEST","Cantidad_salida":20,"Tipo":"Salida","Estado":"{{state}}"}"""))));

        var result = await sender.SendAsync(Job, CancellationToken.None);

        Assert.Equal(expected, result.Outcome);
        Assert.Equal("321", result.ExternalIdentifier);
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
    [InlineData("http://external.example:7147/EbirTest/ODataV4/Company('EBIR')/WS_CPP_SalidasFabrica")]
    [InlineData("http://Navision.EBIR.LOCAL:7147/EbirTest/ODataV4/Company('EBIR')/Other")]
    [InlineData("http://Navision.EBIR.LOCAL:7147/EbirTest/ODataV4/Company('EBIR')/WS_CPP_SalidasFabrica?x=1")]
    public void Options_rejects_endpoint_outside_exact_test_page(string endpoint)
    {
        Assert.Throws<ArgumentException>(() =>
            new NavisionPalletOutputOptions(
                new Uri(endpoint),
                TimeSpan.FromSeconds(10)));
    }

    private static NavisionODataV4PalletOutputSender CreateSender(
        HttpMessageHandler handler) =>
        new(
            new HttpClient(handler),
            new NavisionPalletOutputOptions(Endpoint, TimeSpan.FromSeconds(10)));

    private static HttpResponseMessage Json(HttpStatusCode status, string json) =>
        new(status)
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json")
        };

    private static readonly Uri Endpoint = new(
        "http://Navision.EBIR.LOCAL:7147/EbirTest/ODataV4/Company('EBIR')/WS_CPP_SalidasFabrica");

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
