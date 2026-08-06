using System.Net;
using System.Text;
using System.Text.Json;
using System.Xml.Linq;
using Ebir.Mes.Application.NavisionOutput;
using Ebir.Mes.Integrations.NavisionOutput;
using Xunit;

namespace Ebir.Mes.Integrations.Tests.NavisionOutput;

public sealed class NavisionSoapPalletOutputSenderTests
{
    private const string CodeunitNamespace =
        "urn:microsoft-dynamics-schemas/codeunit/WS_CPP_ControlPlanta";

    [Fact]
    public async Task SendAsync_reads_contract_calls_codeunit_and_confirms_one_new_output()
    {
        var requests = new List<CapturedRequest>();
        var outputRead = 0;
        var handler = new StubHandler(async (request, cancellationToken) =>
        {
            requests.Add(await CaptureAsync(request, cancellationToken));
            if (IsEntity(request, "WS_CPP_OPLanzadas"))
                return Json(Order());
            if (IsEntity(request, "WS_CPP_Producto"))
                return Json(Product());
            if (IsEntity(request, "WS_CPP_SalidasFabrica"))
            {
                outputRead++;
                return outputRead == 1
                    ? Json(Output(100, 10))
                    : Json(Output(321, 20), Output(100, 10));
            }
            return SoapResult(true);
        });

        var result = await CreateSender(handler).SendAsync(Job, CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.Confirmed, result.Outcome);
        Assert.Equal("321", result.ExternalIdentifier);
        Assert.Equal(5, requests.Count);
        Assert.All(requests.Take(3), request => Assert.Equal(HttpMethod.Get, request.Method));
        Assert.Equal(HttpMethod.Post, requests[3].Method);
        Assert.Equal(Endpoint, requests[3].Uri);
        Assert.Equal(
            CodeunitNamespace + ":RegistrarSalidaFabricacion",
            requests[3].SoapAction);
        Assert.Equal(HttpMethod.Get, requests[4].Method);

        var orderQuery = Uri.UnescapeDataString(requests[0].Uri.Query);
        Assert.Contains("No eq 'FL-TEST'", orderQuery);
        Assert.Contains("Cód_Lote_Salida", orderQuery);
        Assert.Contains("$top=2", orderQuery);
        var outputQuery = Uri.UnescapeDataString(requests[2].Uri.Query);
        Assert.Contains("Orden eq 'FL-TEST'", outputQuery);
        Assert.Contains("Producto eq 'ITEM-TEST'", outputQuery);
        Assert.Contains("Estado eq 'Registrado'", outputQuery);
        Assert.Contains("Tipo eq 'Salida'", outputQuery);
        Assert.Contains("$top=100", outputQuery);

        var document = XDocument.Parse(requests[3].Body!);
        XNamespace codeunit = CodeunitNamespace;
        var call = document.Descendants(codeunit + "RegistrarSalidaFabricacion").Single();
        Assert.Equal("FL-TEST", call.Element(codeunit + "n_OP")!.Value);
        Assert.Equal("ITEM-TEST", call.Element(codeunit + "n_Producto")!.Value);
        Assert.Equal("LOT-TEST", call.Element(codeunit + "n_Lote")!.Value);
        Assert.Equal("20", call.Element(codeunit + "dec_Cdad")!.Value);
        Assert.Equal(string.Empty, call.Element(codeunit + "cod_Ubicacion")!.Value);
        Assert.Equal("UN", call.Element(codeunit + "unidadMedida")!.Value);
        Assert.Equal("EMP-TEST", call.Element(codeunit + "userBC")!.Value);
        Assert.Equal("L01", call.Element(codeunit + "assemblyLine")!.Value);
    }

    [Fact]
    public async Task SendAsync_blocks_missing_line_mapping_before_any_nav_call()
    {
        var calls = 0;
        var sender = CreateSender(
            new StubHandler((_, _) =>
            {
                calls++;
                return Task.FromResult(Json());
            }),
            new Dictionary<string, string>());

        var result = await sender.SendAsync(Job, CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.PermanentFailure, result.Outcome);
        Assert.Contains("AssemblyLineMappingMissing", result.TechnicalDataJson);
        Assert.Equal(0, calls);
    }

    [Theory]
    [InlineData("", "LOT-TEST", "EMP-TEST", "LINE-TEST")]
    [InlineData("FL-TEST", "", "EMP-TEST", "LINE-TEST")]
    [InlineData("FL-TEST", "LOT-TEST", "", "LINE-TEST")]
    public async Task SendAsync_blocks_incomplete_job_before_any_nav_call(
        string order,
        string lot,
        string employee,
        string line)
    {
        var calls = 0;
        var sender = CreateSender(new StubHandler((_, _) =>
        {
            calls++;
            return Task.FromResult(Json());
        }));
        var job = Job with
        {
            OrderNumber = order,
            LotNumber = lot,
            EmployeeNumber = employee,
            LineCode = line
        };

        var result = await sender.SendAsync(job, CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.PermanentFailure, result.Outcome);
        Assert.Contains("InvalidJob", result.TechnicalDataJson);
        Assert.Equal(0, calls);
    }

    [Fact]
    public async Task SendAsync_marks_transient_preflight_failure_retryable_without_post()
    {
        var methods = new List<HttpMethod>();
        var sender = CreateSender(new StubHandler((request, _) =>
        {
            methods.Add(request.Method);
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable)
            {
                Content = new StringContent("SENSITIVE NAV BODY")
            });
        }));

        var result = await sender.SendAsync(Job, CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.RetryableFailure, result.Outcome);
        Assert.Equal(3, methods.Count);
        Assert.All(methods, method => Assert.Equal(HttpMethod.Get, method));
        Assert.DoesNotContain("SENSITIVE", result.TechnicalDataJson);
    }

    [Fact]
    public async Task SendAsync_blocks_order_mismatch_before_post()
    {
        var methods = new List<HttpMethod>();
        var sender = CreateSender(new StubHandler((request, _) =>
        {
            methods.Add(request.Method);
            return Task.FromResult(Json(Order(product: "OTHER")));
        }));

        var result = await sender.SendAsync(Job, CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.PermanentFailure, result.Outcome);
        Assert.Contains("OrderMismatch", result.TechnicalDataJson);
        Assert.Single(methods);
        Assert.Equal(HttpMethod.Get, methods[0]);
    }

    [Fact]
    public async Task SendAsync_treats_false_codeunit_result_as_definitive()
    {
        var outputReads = 0;
        var sender = CreateSender(new StubHandler((request, _) =>
        {
            if (IsEntity(request, "WS_CPP_OPLanzadas"))
                return Task.FromResult(Json(Order()));
            if (IsEntity(request, "WS_CPP_Producto"))
                return Task.FromResult(Json(Product()));
            if (IsEntity(request, "WS_CPP_SalidasFabrica"))
            {
                outputReads++;
                return Task.FromResult(Json());
            }
            return Task.FromResult(SoapResult(false));
        }));

        var result = await sender.SendAsync(Job, CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.PermanentFailure, result.Outcome);
        Assert.Contains("CodeunitReturnedFalse", result.TechnicalDataJson);
        Assert.Equal(1, outputReads);
    }

    [Fact]
    public async Task SendAsync_treats_definitive_soap_http_as_permanent()
    {
        var outputReads = 0;
        var sender = CreateSender(new StubHandler((request, _) =>
        {
            if (IsEntity(request, "WS_CPP_OPLanzadas"))
                return Task.FromResult(Json(Order()));
            if (IsEntity(request, "WS_CPP_Producto"))
                return Task.FromResult(Json(Product()));
            if (IsEntity(request, "WS_CPP_SalidasFabrica"))
            {
                outputReads++;
                return Task.FromResult(Json());
            }
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.BadRequest)
            {
                Content = new StringContent("SENSITIVE NAV BODY")
            });
        }));

        var result = await sender.SendAsync(Job, CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.PermanentFailure, result.Outcome);
        Assert.Equal(400, result.HttpStatusCode);
        Assert.Equal(1, outputReads);
        Assert.DoesNotContain("SENSITIVE", result.TechnicalDataJson);
    }

    [Fact]
    public async Task SendAsync_reconciles_uncertain_soap_http_without_repeating_post()
    {
        var posts = 0;
        var outputReads = 0;
        var sender = CreateSender(new StubHandler((request, _) =>
        {
            if (IsEntity(request, "WS_CPP_OPLanzadas"))
                return Task.FromResult(Json(Order()));
            if (IsEntity(request, "WS_CPP_Producto"))
                return Task.FromResult(Json(Product()));
            if (IsEntity(request, "WS_CPP_SalidasFabrica"))
            {
                outputReads++;
                return Task.FromResult(
                    outputReads == 1 ? Json() : Json(Output(321, 20)));
            }
            posts++;
            return Task.FromResult(
                new HttpResponseMessage(HttpStatusCode.ServiceUnavailable));
        }));

        var result = await sender.SendAsync(Job, CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.Confirmed, result.Outcome);
        Assert.Equal("321", result.ExternalIdentifier);
        Assert.Equal(503, result.HttpStatusCode);
        Assert.Equal(1, posts);
    }

    [Fact]
    public async Task SendAsync_marks_invalid_soap_unknown_after_reconciliation()
    {
        var posts = 0;
        var sender = CreateSender(new StubHandler((request, _) =>
        {
            if (IsEntity(request, "WS_CPP_OPLanzadas"))
                return Task.FromResult(Json(Order()));
            if (IsEntity(request, "WS_CPP_Producto"))
                return Task.FromResult(Json(Product()));
            if (IsEntity(request, "WS_CPP_SalidasFabrica"))
                return Task.FromResult(Json());
            posts++;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent("<invalid", Encoding.UTF8, "text/xml")
            });
        }));

        var result = await sender.SendAsync(Job, CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.UnknownResult, result.Outcome);
        Assert.Equal(1, posts);
        Assert.Contains("InvalidSoapResponse", result.TechnicalDataJson);
    }

    [Fact]
    public async Task SendAsync_reconciles_transport_uncertainty_without_repeating_post()
    {
        var posts = 0;
        var outputReads = 0;
        var sender = CreateSender(new StubHandler((request, _) =>
        {
            if (IsEntity(request, "WS_CPP_OPLanzadas"))
                return Task.FromResult(Json(Order()));
            if (IsEntity(request, "WS_CPP_Producto"))
                return Task.FromResult(Json(Product()));
            if (IsEntity(request, "WS_CPP_SalidasFabrica"))
            {
                outputReads++;
                return Task.FromResult(
                    outputReads == 1 ? Json(Output(100, 10)) : Json(Output(321, 20)));
            }
            posts++;
            throw new HttpRequestException("Synthetic transport failure");
        }));

        var result = await sender.SendAsync(Job, CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.Confirmed, result.Outcome);
        Assert.Equal("321", result.ExternalIdentifier);
        Assert.Equal(1, posts);
        Assert.DoesNotContain("Synthetic transport failure", result.TechnicalDataJson);
    }

    [Fact]
    public async Task SendAsync_does_not_repeat_post_when_registered_output_is_not_observed()
    {
        var posts = 0;
        var outputReads = 0;
        var sender = CreateSender(new StubHandler((request, _) =>
        {
            if (IsEntity(request, "WS_CPP_OPLanzadas"))
                return Task.FromResult(Json(Order()));
            if (IsEntity(request, "WS_CPP_Producto"))
                return Task.FromResult(Json(Product()));
            if (IsEntity(request, "WS_CPP_SalidasFabrica"))
            {
                outputReads++;
                return Task.FromResult(Json());
            }
            posts++;
            return Task.FromResult(SoapResult(true));
        }));

        var result = await sender.SendAsync(Job, CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.UnknownResult, result.Outcome);
        Assert.Equal(1, posts);
        Assert.Equal(4, outputReads);
    }

    [Fact]
    public async Task SendAsync_rejects_ambiguous_multiple_new_outputs()
    {
        var outputReads = 0;
        var sender = CreateSender(new StubHandler((request, _) =>
        {
            if (IsEntity(request, "WS_CPP_OPLanzadas"))
                return Task.FromResult(Json(Order()));
            if (IsEntity(request, "WS_CPP_Producto"))
                return Task.FromResult(Json(Product()));
            if (IsEntity(request, "WS_CPP_SalidasFabrica"))
            {
                outputReads++;
                return Task.FromResult(outputReads == 1
                    ? Json(Output(100, 10))
                    : Json(Output(321, 20), Output(322, 20)));
            }
            return Task.FromResult(SoapResult(true));
        }));

        var result = await sender.SendAsync(Job, CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.UnknownResult, result.Outcome);
        Assert.Null(result.ExternalIdentifier);
        Assert.Contains("MultipleNewOutputs", result.TechnicalDataJson);
    }

    [Theory]
    [InlineData("http://external.example:7147/EbirTest/WS/EBIR/Codeunit/WS_CPP_ControlPlanta")]
    [InlineData("http://Navision.EBIR.LOCAL:7147/EbirTest/ODataV4/Company('EBIR')/WS_CPP_ControlPlanta")]
    [InlineData("http://Navision.EBIR.LOCAL:7147/EbirTest/WS/OTHER/Codeunit/WS_CPP_ControlPlanta")]
    [InlineData("http://Navision.EBIR.LOCAL:7147/EbirTest/WS/EBIR/Codeunit/WS_CPP_ControlPlanta?x=1")]
    public void Options_rejects_endpoint_outside_exact_test_codeunit(string endpoint)
    {
        Assert.Throws<ArgumentException>(() =>
            new NavisionPalletOutputOptions(
                new Uri(endpoint),
                TimeSpan.FromSeconds(10),
                LineMappings));
    }

    private static NavisionSoapPalletOutputSender CreateSender(
        HttpMessageHandler handler,
        IReadOnlyDictionary<string, string>? mappings = null) =>
        new(
            new HttpClient(handler),
            new NavisionPalletOutputOptions(
                Endpoint,
                TimeSpan.FromSeconds(10),
                mappings ?? LineMappings));

    private static bool IsEntity(HttpRequestMessage request, string entity) =>
        request.Method == HttpMethod.Get
        && request.RequestUri!.AbsolutePath.EndsWith(
            "/" + entity,
            StringComparison.Ordinal);

    private static async Task<CapturedRequest> CaptureAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken) =>
        new(
            request.Method,
            request.RequestUri!,
            request.Headers.TryGetValues("SOAPAction", out var actions)
                ? actions.Single()
                : null,
            request.Content is null
                ? null
                : await request.Content.ReadAsStringAsync(cancellationToken));

    private static HttpResponseMessage Json(params object[] records) =>
        new(HttpStatusCode.OK)
        {
            Content = new StringContent(
                JsonSerializer.Serialize(new { value = records }),
                Encoding.UTF8,
                "application/json")
        };

    private static object Order(
        string product = "ITEM-TEST",
        string lot = "LOT-TEST",
        string bin = "") =>
        new Dictionary<string, object>
        {
            ["No"] = "FL-TEST",
            ["Source_No"] = product,
            ["Bin_Code"] = bin,
            ["Cód_Lote_Salida"] = lot
        };

    private static object Product() => new
    {
        No = "ITEM-TEST",
        Base_Unit_of_Measure = "UN"
    };

    private static object Output(int id, decimal quantity) => new
    {
        Id = id,
        Orden = "FL-TEST",
        Producto = "ITEM-TEST",
        Cantidad_salida = quantity,
        Estado = "Registrado",
        Tipo = "Salida"
    };

    private static HttpResponseMessage SoapResult(bool value) =>
        new(HttpStatusCode.OK)
        {
            Content = new StringContent(
                $$"""
                <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
                  <s:Body>
                    <RegistrarSalidaFabricacion_Result xmlns="{{CodeunitNamespace}}">
                      <return_value>{{value.ToString().ToLowerInvariant()}}</return_value>
                    </RegistrarSalidaFabricacion_Result>
                  </s:Body>
                </s:Envelope>
                """,
                Encoding.UTF8,
                "text/xml")
        };

    private static readonly IReadOnlyDictionary<string, string> LineMappings =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["LINE-TEST"] = "L01"
        };

    private static readonly Uri Endpoint = new(
        "http://Navision.EBIR.LOCAL:7147/EbirTest/WS/EBIR/Codeunit/WS_CPP_ControlPlanta");

    private static readonly NavisionPalletOutputJob Job = new(
        7,
        Guid.Parse("11111111-1111-1111-1111-111111111111"),
        "MES:PALET:synthetic",
        "FL-TEST",
        "ITEM-TEST",
        "LOT-TEST",
        "EMP-TEST",
        "LINE-TEST",
        20,
        new DateTimeOffset(2026, 8, 6, 10, 30, 0, TimeSpan.Zero),
        1);

    private sealed record CapturedRequest(
        HttpMethod Method,
        Uri Uri,
        string? SoapAction,
        string? Body);

    private sealed class StubHandler(
        Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send)
        : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken) => send(request, cancellationToken);
    }
}
