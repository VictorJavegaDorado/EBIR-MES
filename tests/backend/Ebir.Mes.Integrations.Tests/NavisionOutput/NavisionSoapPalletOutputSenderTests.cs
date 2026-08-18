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
        Assert.Contains("Tipo eq 'Salida'", outputQuery);
        Assert.DoesNotContain("Estado eq", outputQuery);
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
    public async Task SendAsync_accepts_empty_nav_lot_and_keeps_mes_traceability_lot()
    {
        CapturedRequest? registrar = null;
        var outputReads = 0;
        var handler = new StubHandler(async (request, cancellationToken) =>
        {
            if (IsEntity(request, "WS_CPP_OPLanzadas"))
                return Json(Order(lot: string.Empty));
            if (IsEntity(request, "WS_CPP_Producto"))
                return Json(Product());
            if (IsEntity(request, "WS_CPP_SalidasFabrica"))
            {
                outputReads++;
                return outputReads == 1 ? Json() : Json(Output(321, 20));
            }
            if (request.Headers.TryGetValues("SOAPAction", out var actions)
                && actions.Single().EndsWith(
                    ":RegistrarSalidaFabricacion",
                    StringComparison.Ordinal))
            {
                registrar = await CaptureAsync(request, cancellationToken);
            }
            return SoapResult(true);
        });

        var result = await CreateSender(handler).SendAsync(Job, CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.Confirmed, result.Outcome);
        Assert.NotNull(registrar);
        var document = XDocument.Parse(registrar.Body!);
        XNamespace codeunit = CodeunitNamespace;
        var call = document.Descendants(
            codeunit + "RegistrarSalidaFabricacion").Single();
        Assert.Equal("LOT-TEST", call.Element(codeunit + "n_Lote")!.Value);
    }

    [Fact]
    public async Task SendAsync_blocks_nonempty_nav_lot_mismatch_before_post()
    {
        var methods = new List<HttpMethod>();
        var sender = CreateSender(new StubHandler((request, _) =>
        {
            methods.Add(request.Method);
            return Task.FromResult(Json(Order(lot: "OTHER-LOT")));
        }));

        var result = await sender.SendAsync(Job, CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.PermanentFailure, result.Outcome);
        Assert.Contains("OrderMismatch", result.TechnicalDataJson);
        Assert.Single(methods);
        Assert.Equal(HttpMethod.Get, methods[0]);
    }

    [Fact]
    public async Task SendAsync_reconciles_false_codeunit_result_and_preserves_pending_output()
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
                return Task.FromResult(outputReads == 1
                    ? Json()
                    : Json(Output(321, 20, "Pendiente")));
            }
            posts++;
            return Task.FromResult(SoapResult(false));
        }));

        var result = await sender.SendAsync(Job, CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.UnknownResult, result.Outcome);
        Assert.Equal("321", result.ExternalIdentifier);
        Assert.Contains("OutputStillPending", result.TechnicalDataJson);
        Assert.Equal(1, posts);
        Assert.Equal(2, outputReads);
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
        Assert.Equal(12, outputReads);
    }

    [Fact]
    public async Task SendAsync_preserves_pending_output_id_for_later_reconciliation()
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
                return Task.FromResult(outputReads == 1
                    ? Json()
                    : Json(Output(321, 20, "Pendiente")));
            }
            posts++;
            return Task.FromResult(SoapResult(true));
        }));

        var result = await sender.SendAsync(Job, CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.UnknownResult, result.Outcome);
        Assert.Equal("321", result.ExternalIdentifier);
        Assert.Equal(1, posts);
        Assert.Equal(2, outputReads);
        Assert.Contains("OutputStillPending", result.TechnicalDataJson);
    }

    [Fact]
    public async Task SendAsync_observes_output_published_after_initial_reconciliation_reads()
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
                return Task.FromResult(outputReads < 4
                    ? Json()
                    : Json(Output(321, 20, "Pendiente")));
            }
            posts++;
            return Task.FromResult(SoapResult(false));
        }));

        var result = await sender.SendAsync(Job, CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.UnknownResult, result.Outcome);
        Assert.Equal("321", result.ExternalIdentifier);
        Assert.Equal(1, posts);
        Assert.Equal(4, outputReads);
        Assert.Contains("OutputStillPending", result.TechnicalDataJson);
    }

    [Fact]
    public async Task SendAsync_reconciles_existing_identifier_without_output_post()
    {
        var requests = new List<CapturedRequest>();
        var handler = new StubHandler(async (request, cancellationToken) =>
        {
            requests.Add(await CaptureAsync(request, cancellationToken));
            return Json(Output(321, 20));
        });
        var job = Job with { ExternalIdentifier = "321" };

        var result = await CreateSender(handler)
            .SendAsync(job, CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.Confirmed, result.Outcome);
        Assert.Equal("321", result.ExternalIdentifier);
        Assert.Single(requests);
        Assert.Equal(HttpMethod.Get, requests[0].Method);
        var query = Uri.UnescapeDataString(requests[0].Uri.Query);
        Assert.Contains("Id eq 321", query);
        Assert.Contains("$top=2", query);
    }

    [Fact]
    public async Task SendAsync_keeps_existing_pending_identifier_unknown()
    {
        var sender = CreateSender(new StubHandler((request, _) =>
        {
            Assert.Equal(HttpMethod.Get, request.Method);
            return Task.FromResult(Json(Output(321, 20, "Pendiente")));
        }));

        var result = await sender.SendAsync(
            Job with { ExternalIdentifier = "321" },
            CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.UnknownResult, result.Outcome);
        Assert.Equal("321", result.ExternalIdentifier);
        Assert.Contains("OutputStillPending", result.TechnicalDataJson);
    }

    [Fact]
    public async Task SendAsync_opens_registers_and_closes_nav_pallet_in_order()
    {
        var actions = new List<string>();
        var captured = new List<CapturedRequest>();
        var isOpen = false;
        var outputReads = 0;
        var handler = new StubHandler(async (request, cancellationToken) =>
        {
            if (request.Method == HttpMethod.Get)
            {
                if (IsEntity(request, "WS_CPP_OPLanzadas"))
                    return Json(Order());
                if (IsEntity(request, "WS_CPP_Producto"))
                    return Json(Product());
                outputReads++;
                return outputReads == 1 ? Json() : Json(Output(321, 20));
            }

            var call = await CaptureAsync(request, cancellationToken);
            captured.Add(call);
            var action = SoapOperation(request);
            actions.Add(action);
            if (action == "IsOpenPallet")
                return SoapBooleanResult("IsOpenPallet", isOpen);
            if (action == "OpenClosePalletMES")
            {
                isOpen = !isOpen;
                return SoapVoidResult("OpenClosePalletMES");
            }
            return SoapResult(true);
        });

        var result = await CreateSender(
                handler,
                emulatePalletLifecycle: false)
            .SendAsync(Job, CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.Confirmed, result.Outcome);
        Assert.Equal("321", result.ExternalIdentifier);
        Assert.False(isOpen);
        Assert.Equal(
            new[]
            {
                "IsOpenPallet", "OpenClosePalletMES", "IsOpenPallet",
                "RegistrarSalidaFabricacion",
                "IsOpenPallet", "OpenClosePalletMES", "IsOpenPallet"
            },
            actions);

        XNamespace codeunit = CodeunitNamespace;
        var toggle = XDocument.Parse(
                captured.First(request =>
                    request.SoapAction!.EndsWith(":OpenClosePalletMES", StringComparison.Ordinal))
                    .Body!)
            .Descendants(codeunit + "OpenClosePalletMES")
            .Single();
        Assert.DoesNotContain(
            captured,
            request => request.SoapAction?.EndsWith(
                ":OpenClosePallet",
                StringComparison.Ordinal) == true);
        Assert.Equal("FL-TEST", toggle.Element(codeunit + "productionOrderNo")!.Value);
        Assert.Equal("EMP-TEST", toggle.Element(codeunit + "userBC")!.Value);
        Assert.Equal("ITEM-TEST", toggle.Element(codeunit + "itemNo")!.Value);
        Assert.Equal("0", toggle.Element(codeunit + "partialQuantity")!.Value);
        Assert.Equal("L01", toggle.Element(codeunit + "assemblyLine")!.Value);
    }

    [Fact]
    public async Task SendAsync_does_not_repeat_uncertain_open_toggle_when_state_is_observed()
    {
        var isOpen = false;
        var toggles = 0;
        var registrarPosts = 0;
        var outputReads = 0;
        var handler = new StubHandler((request, _) =>
        {
            if (request.Method == HttpMethod.Get)
            {
                if (IsEntity(request, "WS_CPP_OPLanzadas"))
                    return Task.FromResult(Json(Order()));
                if (IsEntity(request, "WS_CPP_Producto"))
                    return Task.FromResult(Json(Product()));
                outputReads++;
                return Task.FromResult(
                    outputReads == 1 ? Json() : Json(Output(321, 20)));
            }

            return SoapOperation(request) switch
            {
                "IsOpenPallet" => Task.FromResult(
                    SoapBooleanResult("IsOpenPallet", isOpen)),
                "OpenClosePalletMES" => Toggle(),
                _ => Register()
            };

            Task<HttpResponseMessage> Toggle()
            {
                toggles++;
                isOpen = !isOpen;
                return Task.FromResult(toggles == 1
                    ? new HttpResponseMessage(HttpStatusCode.InternalServerError)
                    : SoapVoidResult("OpenClosePalletMES"));
            }

            Task<HttpResponseMessage> Register()
            {
                registrarPosts++;
                return Task.FromResult(SoapResult(true));
            }
        });

        var result = await CreateSender(
                handler,
                emulatePalletLifecycle: false)
            .SendAsync(Job, CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.Confirmed, result.Outcome);
        Assert.Equal(2, toggles);
        Assert.Equal(1, registrarPosts);
        Assert.False(isOpen);
    }

    [Fact]
    public async Task SendAsync_blocks_output_when_open_state_is_not_observed()
    {
        var toggles = 0;
        var registrarPosts = 0;
        var handler = new StubHandler((request, _) =>
        {
            if (request.Method == HttpMethod.Get)
            {
                if (IsEntity(request, "WS_CPP_OPLanzadas"))
                    return Task.FromResult(Json(Order()));
                if (IsEntity(request, "WS_CPP_Producto"))
                    return Task.FromResult(Json(Product()));
                return Task.FromResult(Json());
            }

            if (SoapOperation(request) == "IsOpenPallet")
                return Task.FromResult(SoapBooleanResult("IsOpenPallet", false));
            if (SoapOperation(request) == "OpenClosePalletMES")
            {
                toggles++;
                return Task.FromResult(SoapVoidResult("OpenClosePalletMES"));
            }
            registrarPosts++;
            return Task.FromResult(SoapResult(true));
        });

        var result = await CreateSender(
                handler,
                emulatePalletLifecycle: false)
            .SendAsync(Job, CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.UnknownResult, result.Outcome);
        Assert.Contains("PalletOpenNotObserved", result.TechnicalDataJson);
        Assert.Equal(1, toggles);
        Assert.Equal(0, registrarPosts);
    }

    [Fact]
    public async Task SendAsync_preserves_output_id_when_close_state_is_not_observed()
    {
        var isOpen = false;
        var toggles = 0;
        var registrarPosts = 0;
        var outputReads = 0;
        var handler = new StubHandler((request, _) =>
        {
            if (request.Method == HttpMethod.Get)
            {
                if (IsEntity(request, "WS_CPP_OPLanzadas"))
                    return Task.FromResult(Json(Order()));
                if (IsEntity(request, "WS_CPP_Producto"))
                    return Task.FromResult(Json(Product()));
                outputReads++;
                return Task.FromResult(
                    outputReads == 1 ? Json() : Json(Output(321, 20)));
            }

            var operation = SoapOperation(request);
            if (operation == "IsOpenPallet")
                return Task.FromResult(SoapBooleanResult("IsOpenPallet", isOpen));
            if (operation == "OpenClosePalletMES")
            {
                toggles++;
                if (toggles == 1)
                    isOpen = true;
                return Task.FromResult(SoapVoidResult("OpenClosePalletMES"));
            }

            registrarPosts++;
            return Task.FromResult(SoapResult(true));
        });

        var result = await CreateSender(
                handler,
                emulatePalletLifecycle: false)
            .SendAsync(Job, CancellationToken.None);

        Assert.Equal(NavisionPalletOutputDeliveryOutcome.UnknownResult, result.Outcome);
        Assert.Equal("321", result.ExternalIdentifier);
        Assert.Contains("PalletCloseNotObserved", result.TechnicalDataJson);
        Assert.Equal(2, toggles);
        Assert.Equal(1, registrarPosts);
        Assert.True(isOpen);
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

    [Fact]
    public void Options_rejects_invalid_reconciliation_observation_delays()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            new NavisionPalletOutputOptions(
                Endpoint,
                TimeSpan.FromSeconds(10),
                LineMappings,
                [TimeSpan.Zero]));
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            new NavisionPalletOutputOptions(
                Endpoint,
                TimeSpan.FromSeconds(10),
                LineMappings,
                []));
    }

    [Fact]
    public void Options_defaults_to_thirty_second_reconciliation_window()
    {
        var options = new NavisionPalletOutputOptions(
            Endpoint,
            TimeSpan.FromSeconds(10),
            LineMappings);

        Assert.Equal(10, options.ReconciliationObservationDelays.Count);
        Assert.Equal(
            TimeSpan.FromSeconds(30),
            options.ReconciliationObservationDelays.Aggregate(
                TimeSpan.Zero,
                (total, delay) => total + delay));
    }

    private static NavisionSoapPalletOutputSender CreateSender(
        HttpMessageHandler handler,
        IReadOnlyDictionary<string, string>? mappings = null,
        bool emulatePalletLifecycle = true) =>
        new(
            new HttpClient(
                emulatePalletLifecycle
                    ? new PalletLifecycleHandler(handler)
                    : handler),
            new NavisionPalletOutputOptions(
                Endpoint,
                TimeSpan.FromSeconds(10),
                mappings ?? LineMappings,
                Enumerable.Repeat(TimeSpan.FromMilliseconds(1), 10).ToArray()));

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

    private static object Output(
        int id,
        decimal quantity,
        string state = "Registrado") => new
    {
        Id = id,
        Orden = "FL-TEST",
        Producto = "ITEM-TEST",
        Cantidad_salida = quantity,
        Estado = state,
        Tipo = "Salida"
    };

    private static HttpResponseMessage SoapResult(bool value) =>
        SoapBooleanResult("RegistrarSalidaFabricacion", value);

    private static HttpResponseMessage SoapBooleanResult(
        string operation,
        bool value) =>
        new(HttpStatusCode.OK)
        {
            Content = new StringContent(
                $$"""
                <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
                  <s:Body>
                    <{{operation}}_Result xmlns="{{CodeunitNamespace}}">
                      <return_value>{{value.ToString().ToLowerInvariant()}}</return_value>
                    </{{operation}}_Result>
                  </s:Body>
                </s:Envelope>
                """,
                Encoding.UTF8,
                "text/xml")
        };

    private static HttpResponseMessage SoapVoidResult(string operation) =>
        new(HttpStatusCode.OK)
        {
            Content = new StringContent(
                $$"""
                <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
                  <s:Body>
                    <{{operation}}_Result xmlns="{{CodeunitNamespace}}" />
                  </s:Body>
                </s:Envelope>
                """,
                Encoding.UTF8,
                "text/xml")
        };

    private static string SoapOperation(HttpRequestMessage request) =>
        request.Headers.GetValues("SOAPAction")
            .Single()
            .Split(':')
            .Last();

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
        1,
        null);

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

    private sealed class PalletLifecycleHandler(HttpMessageHandler innerHandler)
        : DelegatingHandler(innerHandler)
    {
        private bool isOpen;

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            if (request.Method == HttpMethod.Post
                && request.Headers.Contains("SOAPAction"))
            {
                var operation = SoapOperation(request);
                if (operation == "IsOpenPallet")
                {
                    return Task.FromResult(
                        SoapBooleanResult("IsOpenPallet", isOpen));
                }
                if (operation == "OpenClosePalletMES")
                {
                    isOpen = !isOpen;
                    return Task.FromResult(SoapVoidResult("OpenClosePalletMES"));
                }
            }

            return base.SendAsync(request, cancellationToken);
        }
    }
}
