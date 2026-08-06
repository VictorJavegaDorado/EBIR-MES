using System.Globalization;
using System.Net;
using System.Text;
using System.Text.Json;
using System.Xml;
using System.Xml.Linq;
using Ebir.Mes.Application.NavisionOutput;

namespace Ebir.Mes.Integrations.NavisionOutput;

public sealed class NavisionSoapPalletOutputSender(
    HttpClient httpClient,
    NavisionPalletOutputOptions options) : INavisionPalletOutputSender
{
    private const int MaximumResponseBytes = 128 * 1024;
    private const int MaximumODataRecords = 100;
    private const int MaximumReadAttempts = 3;
    private const string SoapEnvelopeNamespace =
        "http://schemas.xmlsoap.org/soap/envelope/";
    private const string CodeunitNamespace =
        "urn:microsoft-dynamics-schemas/codeunit/WS_CPP_ControlPlanta";

    public async Task<NavisionPalletOutputReceipt> SendAsync(
        NavisionPalletOutputJob job,
        CancellationToken cancellationToken)
    {
        var reconciliationOnly = !string.IsNullOrWhiteSpace(job.ExternalIdentifier);
        var validation = ValidateJob(job, true, out var assemblyLine);
        if (validation is not null)
            return validation;

        if (reconciliationOnly)
            return await ReconcileExistingAsync(
                job,
                assemblyLine!,
                cancellationToken);

        OrderRecord order;
        ProductRecord product;
        IReadOnlyList<OutputRecord> baseline;
        try
        {
            order = await ReadOrderAsync(job.OrderNumber, cancellationToken);
            if (!string.Equals(order.ProductNumber, job.ProductNumber,
                    StringComparison.Ordinal)
                || !string.Equals(order.LotNumber, job.LotNumber,
                    StringComparison.Ordinal))
            {
                return Receipt(
                    NavisionPalletOutputDeliveryOutcome.PermanentFailure,
                    null,
                    "OrderMismatch");
            }

            product = await ReadProductAsync(job.ProductNumber, cancellationToken);
            baseline = await ReadOutputsAsync(job, cancellationToken);
            if (baseline.Count >= MaximumODataRecords)
            {
                return Receipt(
                    NavisionPalletOutputDeliveryOutcome.PermanentFailure,
                    null,
                    "BaselineTruncated");
            }
        }
        catch (NavisionReadException exception)
        {
            return Receipt(
                exception.IsTransient
                    ? NavisionPalletOutputDeliveryOutcome.RetryableFailure
                    : NavisionPalletOutputDeliveryOutcome.PermanentFailure,
                exception.HttpStatusCode,
                exception.Reason);
        }

        var baselineMaximumId = baseline.Count == 0 ? 0 : baseline.Max(row => row.Id);
        var openPallet = await EnsurePalletStateAsync(
            job,
            assemblyLine!,
            expectedOpen: true,
            cancellationToken);
        if (!openPallet.Succeeded)
        {
            return Receipt(
                openPallet.Outcome,
                openPallet.HttpStatusCode,
                openPallet.Reason,
                baselineMaximumId: baselineMaximumId);
        }

        var attempt = await SendCodeunitAsync(
            job,
            order.BinCode,
            product.UnitOfMeasure,
            assemblyLine!,
            cancellationToken);

        if (attempt.IsDefinitiveRejection)
        {
            return await ClosePalletAsync(
                job,
                assemblyLine!,
                Receipt(
                    NavisionPalletOutputDeliveryOutcome.PermanentFailure,
                    attempt.HttpStatusCode,
                    attempt.Reason,
                    baselineMaximumId: baselineMaximumId),
                baselineMaximumId,
                cancellationToken);
        }

        var outputReceipt = await ReconcileAsync(
            job,
            baselineMaximumId,
            attempt,
            cancellationToken);
        return await ClosePalletAsync(
            job,
            assemblyLine!,
            outputReceipt,
            baselineMaximumId,
            cancellationToken);
    }

    private NavisionPalletOutputReceipt? ValidateJob(
        NavisionPalletOutputJob job,
        bool requireAssemblyLine,
        out string? assemblyLine)
    {
        assemblyLine = null;
        if (string.IsNullOrWhiteSpace(job.OrderNumber)
            || string.IsNullOrWhiteSpace(job.ProductNumber)
            || string.IsNullOrWhiteSpace(job.LotNumber)
            || string.IsNullOrWhiteSpace(job.EmployeeNumber)
            || string.IsNullOrWhiteSpace(job.LineCode)
            || job.GoodQuantity <= 0)
        {
            return Receipt(
                NavisionPalletOutputDeliveryOutcome.PermanentFailure,
                null,
                "InvalidJob");
        }

        if (requireAssemblyLine
            && !options.TryResolveAssemblyLine(job.LineCode, out assemblyLine))
        {
            return Receipt(
                NavisionPalletOutputDeliveryOutcome.PermanentFailure,
                null,
                "AssemblyLineMappingMissing");
        }

        return null;
    }

    private async Task<OrderRecord> ReadOrderAsync(
        string orderNumber,
        CancellationToken cancellationToken)
    {
        var records = await ReadODataAsync(
            CreateODataEndpoint(
                "WS_CPP_OPLanzadas",
                $"No eq '{EscapeODataLiteral(orderNumber)}'",
                "No,Source_No,Bin_Code,C%C3%B3d_Lote_Salida",
                2),
            element => new OrderRecord(
                RequiredString(element, "No"),
                RequiredString(element, "Source_No"),
                RequiredString(element, "Cód_Lote_Salida"),
                OptionalString(element, "Bin_Code")),
            cancellationToken);
        if (records.Count != 1
            || !string.Equals(records[0].OrderNumber, orderNumber,
                StringComparison.Ordinal))
        {
            throw new NavisionReadException(false, null, "OrderNotUnique");
        }
        return records[0];
    }

    private async Task<ProductRecord> ReadProductAsync(
        string productNumber,
        CancellationToken cancellationToken)
    {
        var records = await ReadODataAsync(
            CreateODataEndpoint(
                "WS_CPP_Producto",
                $"No eq '{EscapeODataLiteral(productNumber)}'",
                "No,Base_Unit_of_Measure",
                2),
            element => new ProductRecord(
                RequiredString(element, "No"),
                RequiredString(element, "Base_Unit_of_Measure")),
            cancellationToken);
        if (records.Count != 1
            || !string.Equals(records[0].ProductNumber, productNumber,
                StringComparison.Ordinal))
        {
            throw new NavisionReadException(false, null, "ProductNotUnique");
        }
        return records[0];
    }

    private Task<IReadOnlyList<OutputRecord>> ReadOutputsAsync(
        NavisionPalletOutputJob job,
        CancellationToken cancellationToken) =>
        ReadODataAsync(
            CreateODataEndpoint(
                "WS_CPP_SalidasFabrica",
                $"Orden eq '{EscapeODataLiteral(job.OrderNumber)}' and " +
                $"Producto eq '{EscapeODataLiteral(job.ProductNumber)}' and " +
                "Tipo eq 'Salida'",
                "Id,Orden,Producto,Cantidad_salida,Estado,Tipo",
                MaximumODataRecords,
                "Id desc"),
            element => new OutputRecord(
                RequiredPositiveInt(element, "Id"),
                RequiredString(element, "Orden"),
                RequiredString(element, "Producto"),
                RequiredDecimal(element, "Cantidad_salida"),
                RequiredString(element, "Estado"),
                RequiredString(element, "Tipo")),
            cancellationToken);

    private async Task<NavisionPalletOutputReceipt> ReconcileExistingAsync(
        NavisionPalletOutputJob job,
        string assemblyLine,
        CancellationToken cancellationToken)
    {
        if (!int.TryParse(
                job.ExternalIdentifier,
                NumberStyles.None,
                CultureInfo.InvariantCulture,
                out var externalId)
            || externalId <= 0)
        {
            return Receipt(
                NavisionPalletOutputDeliveryOutcome.UnknownResult,
                null,
                "ExternalIdentifierInvalid",
                job.ExternalIdentifier);
        }

        try
        {
            var outputs = await ReadODataAsync(
                CreateODataEndpoint(
                    "WS_CPP_SalidasFabrica",
                    $"Id eq {externalId.ToString(CultureInfo.InvariantCulture)}",
                    "Id,Orden,Producto,Cantidad_salida,Estado,Tipo",
                    2),
                element => new OutputRecord(
                    RequiredPositiveInt(element, "Id"),
                    RequiredString(element, "Orden"),
                    RequiredString(element, "Producto"),
                    RequiredDecimal(element, "Cantidad_salida"),
                    RequiredString(element, "Estado"),
                    RequiredString(element, "Tipo")),
                cancellationToken);

            if (outputs.Count != 1)
            {
                return Receipt(
                    NavisionPalletOutputDeliveryOutcome.UnknownResult,
                    null,
                    "ReconciliationRowNotUnique",
                    job.ExternalIdentifier);
            }

            var output = outputs[0];
            if (output.Id != externalId
                || !string.Equals(output.OrderNumber, job.OrderNumber,
                    StringComparison.Ordinal)
                || !string.Equals(output.ProductNumber, job.ProductNumber,
                    StringComparison.Ordinal)
                || output.Quantity != job.GoodQuantity
                || !string.Equals(output.Type, "Salida", StringComparison.Ordinal))
            {
                return Receipt(
                    NavisionPalletOutputDeliveryOutcome.UnknownResult,
                    null,
                    "ReconciliationMismatch",
                    job.ExternalIdentifier);
            }

            var outputReceipt = string.Equals(
                    output.State,
                    "Registrado",
                    StringComparison.Ordinal)
                ? Receipt(
                    NavisionPalletOutputDeliveryOutcome.Confirmed,
                    null,
                    "ReconciledRegisteredOutput",
                    job.ExternalIdentifier)
                : Receipt(
                    NavisionPalletOutputDeliveryOutcome.UnknownResult,
                    null,
                    string.Equals(output.State, "Pendiente", StringComparison.Ordinal)
                        ? "OutputStillPending"
                        : "OutputStateNotRegistered",
                    job.ExternalIdentifier);
            return await ClosePalletAsync(
                job,
                assemblyLine,
                outputReceipt,
                baselineMaximumId: null,
                cancellationToken);
        }
        catch (NavisionReadException exception)
        {
            return Receipt(
                NavisionPalletOutputDeliveryOutcome.UnknownResult,
                exception.HttpStatusCode,
                exception.Reason,
                job.ExternalIdentifier);
        }
    }

    private async Task<NavisionPalletOutputReceipt> ClosePalletAsync(
        NavisionPalletOutputJob job,
        string assemblyLine,
        NavisionPalletOutputReceipt outputReceipt,
        int? baselineMaximumId,
        CancellationToken cancellationToken)
    {
        var closePallet = await EnsurePalletStateAsync(
            job,
            assemblyLine,
            expectedOpen: false,
            cancellationToken);
        if (closePallet.Succeeded)
            return outputReceipt;

        return Receipt(
            NavisionPalletOutputDeliveryOutcome.UnknownResult,
            closePallet.HttpStatusCode ?? outputReceipt.HttpStatusCode,
            closePallet.Reason,
            outputReceipt.ExternalIdentifier,
            baselineMaximumId);
    }

    private async Task<PalletStateTransition> EnsurePalletStateAsync(
        NavisionPalletOutputJob job,
        string assemblyLine,
        bool expectedOpen,
        CancellationToken cancellationToken)
    {
        bool isOpen;
        try
        {
            isOpen = await ReadPalletOpenAsync(
                job.OrderNumber,
                assemblyLine,
                cancellationToken);
        }
        catch (NavisionReadException exception)
        {
            return new(
                false,
                exception.IsTransient
                    ? NavisionPalletOutputDeliveryOutcome.RetryableFailure
                    : NavisionPalletOutputDeliveryOutcome.PermanentFailure,
                exception.HttpStatusCode,
                exception.Reason);
        }

        if (isOpen == expectedOpen)
            return PalletStateTransition.Success;

        var toggle = await SendPalletToggleAsync(
            job,
            assemblyLine,
            cancellationToken);
        try
        {
            isOpen = await ReadPalletOpenAsync(
                job.OrderNumber,
                assemblyLine,
                cancellationToken);
        }
        catch (NavisionReadException exception)
        {
            return new(
                false,
                toggle.IsDefinitiveRejection
                    ? NavisionPalletOutputDeliveryOutcome.PermanentFailure
                    : NavisionPalletOutputDeliveryOutcome.UnknownResult,
                toggle.HttpStatusCode ?? exception.HttpStatusCode,
                expectedOpen
                    ? "PalletOpenStateUnavailable"
                    : "PalletCloseStateUnavailable");
        }

        if (isOpen == expectedOpen)
            return PalletStateTransition.Success;

        return new(
            false,
            toggle.IsDefinitiveRejection
                ? NavisionPalletOutputDeliveryOutcome.PermanentFailure
                : NavisionPalletOutputDeliveryOutcome.UnknownResult,
            toggle.HttpStatusCode,
            expectedOpen ? "PalletOpenNotObserved" : "PalletCloseNotObserved");
    }

    private async Task<bool> ReadPalletOpenAsync(
        string orderNumber,
        string assemblyLine,
        CancellationToken cancellationToken)
    {
        for (var attempt = 1; attempt <= MaximumReadAttempts; attempt++)
        {
            using var request = CreateIsOpenPalletRequest(orderNumber, assemblyLine);
            using var timeout =
                CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(options.RequestTimeout);
            try
            {
                using var response = await httpClient.SendAsync(
                    request,
                    HttpCompletionOption.ResponseHeadersRead,
                    timeout.Token);
                var status = (int)response.StatusCode;
                if (!response.IsSuccessStatusCode)
                {
                    var transient = response.StatusCode is HttpStatusCode.RequestTimeout
                        or HttpStatusCode.TooManyRequests
                        || status >= 500;
                    if (transient && attempt < MaximumReadAttempts)
                        continue;
                    throw new NavisionReadException(
                        transient,
                        status,
                        "IsOpenPalletHttpFailure");
                }

                var result = await ReadBooleanCodeunitResultAsync(
                    response,
                    "IsOpenPallet_Result",
                    timeout.Token);
                if (result is not null)
                    return result.Value;
                throw new NavisionReadException(
                    false,
                    status,
                    "InvalidIsOpenPalletResponse");
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (OperationCanceledException exception)
            {
                if (attempt == MaximumReadAttempts)
                    throw new NavisionReadException(
                        true,
                        null,
                        exception.GetType().Name);
            }
            catch (HttpRequestException exception)
            {
                if (attempt == MaximumReadAttempts)
                {
                    throw new NavisionReadException(
                        true,
                        exception.StatusCode is null
                            ? null
                            : (int)exception.StatusCode.Value,
                        exception.GetType().Name);
                }
            }
        }

        throw new NavisionReadException(true, null, "IsOpenPalletUnavailable");
    }

    private async Task<SoapAttempt> SendPalletToggleAsync(
        NavisionPalletOutputJob job,
        string assemblyLine,
        CancellationToken cancellationToken)
    {
        using var request = CreateOpenClosePalletRequest(job, assemblyLine);
        using var timeout =
            CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(options.RequestTimeout);
        try
        {
            using var response = await httpClient.SendAsync(
                request,
                HttpCompletionOption.ResponseHeadersRead,
                timeout.Token);
            var status = (int)response.StatusCode;
            if (response.StatusCode is not HttpStatusCode.OK)
            {
                var uncertain = response.StatusCode is HttpStatusCode.RequestTimeout
                    or HttpStatusCode.TooManyRequests
                    || status >= 500;
                return new SoapAttempt(
                    status,
                    uncertain ? "OpenClosePalletHttpUncertain" : "OpenClosePalletHttpRejected",
                    !uncertain);
            }

            var valid = await ReadVoidCodeunitResultAsync(
                response,
                "OpenClosePallet_Result",
                timeout.Token);
            return valid
                ? new SoapAttempt(status, null, false)
                : new SoapAttempt(status, "InvalidOpenClosePalletResponse", false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (OperationCanceledException exception)
        {
            return new SoapAttempt(null, exception.GetType().Name, false);
        }
        catch (HttpRequestException exception)
        {
            return new SoapAttempt(
                exception.StatusCode is null ? null : (int)exception.StatusCode.Value,
                exception.GetType().Name,
                false);
        }
    }

    private async Task<NavisionPalletOutputReceipt> ReconcileAsync(
        NavisionPalletOutputJob job,
        int baselineMaximumId,
        SoapAttempt attempt,
        CancellationToken cancellationToken)
    {
        for (var readAttempt = 1; readAttempt <= MaximumReadAttempts; readAttempt++)
        {
            try
            {
                var outputs = await ReadOutputsAsync(job, cancellationToken);
                if (outputs.Count >= MaximumODataRecords)
                {
                    return Receipt(
                        NavisionPalletOutputDeliveryOutcome.UnknownResult,
                        attempt.HttpStatusCode,
                        "ReconciliationTruncated",
                        baselineMaximumId: baselineMaximumId);
                }

                var newMatches = outputs
                    .Where(output =>
                        output.Id > baselineMaximumId
                        && string.Equals(output.OrderNumber, job.OrderNumber,
                            StringComparison.Ordinal)
                        && string.Equals(output.ProductNumber, job.ProductNumber,
                            StringComparison.Ordinal)
                        && output.Quantity == job.GoodQuantity
                        && string.Equals(output.Type, "Salida",
                            StringComparison.Ordinal))
                    .ToArray();
                if (newMatches.Length == 1)
                {
                    var match = newMatches[0];
                    if (string.Equals(match.State, "Registrado", StringComparison.Ordinal))
                    {
                        return Receipt(
                            NavisionPalletOutputDeliveryOutcome.Confirmed,
                            attempt.HttpStatusCode,
                            attempt.Reason,
                            match.Id.ToString(CultureInfo.InvariantCulture),
                            baselineMaximumId);
                    }

                    if (readAttempt == MaximumReadAttempts)
                    {
                        return Receipt(
                            NavisionPalletOutputDeliveryOutcome.UnknownResult,
                            attempt.HttpStatusCode,
                            string.Equals(match.State, "Pendiente", StringComparison.Ordinal)
                                ? "OutputStillPending"
                                : "OutputStateNotRegistered",
                            match.Id.ToString(CultureInfo.InvariantCulture),
                            baselineMaximumId);
                    }
                }
                if (newMatches.Length > 1)
                {
                    return Receipt(
                        NavisionPalletOutputDeliveryOutcome.UnknownResult,
                        attempt.HttpStatusCode,
                        "MultipleNewOutputs",
                        baselineMaximumId: baselineMaximumId);
                }
            }
            catch (NavisionReadException exception)
            {
                if (!exception.IsTransient || readAttempt == MaximumReadAttempts)
                {
                    return Receipt(
                        NavisionPalletOutputDeliveryOutcome.UnknownResult,
                        attempt.HttpStatusCode ?? exception.HttpStatusCode,
                        exception.Reason,
                        baselineMaximumId: baselineMaximumId);
                }
            }

            if (readAttempt < MaximumReadAttempts)
                await Task.Delay(TimeSpan.FromMilliseconds(100 * readAttempt),
                    cancellationToken);
        }

        return Receipt(
            NavisionPalletOutputDeliveryOutcome.UnknownResult,
            attempt.HttpStatusCode,
            attempt.Reason ?? "OutputNotObserved",
            baselineMaximumId: baselineMaximumId);
    }

    private async Task<SoapAttempt> SendCodeunitAsync(
        NavisionPalletOutputJob job,
        string binCode,
        string unitOfMeasure,
        string assemblyLine,
        CancellationToken cancellationToken)
    {
        using var request = CreateCodeunitRequest(
            job,
            binCode,
            unitOfMeasure,
            assemblyLine);
        using var timeout =
            CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(options.RequestTimeout);
        try
        {
            using var response = await httpClient.SendAsync(
                request,
                HttpCompletionOption.ResponseHeadersRead,
                timeout.Token);
            var status = (int)response.StatusCode;
            if (response.StatusCode is not HttpStatusCode.OK)
            {
                var uncertain = response.StatusCode is HttpStatusCode.RequestTimeout
                    or HttpStatusCode.TooManyRequests
                    || status >= 500;
                return new SoapAttempt(
                    status,
                    uncertain ? "SoapHttpUncertain" : "SoapHttpRejected",
                    !uncertain);
            }

            var result = await ReadCodeunitResultAsync(response, timeout.Token);
            return result switch
            {
                true => new SoapAttempt(status, null, false),
                false => new SoapAttempt(status, "CodeunitReturnedFalse", true),
                null => new SoapAttempt(status, "InvalidSoapResponse", false)
            };
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (OperationCanceledException exception)
        {
            return new SoapAttempt(null, exception.GetType().Name, false);
        }
        catch (HttpRequestException exception)
        {
            return new SoapAttempt(
                exception.StatusCode is null ? null : (int)exception.StatusCode.Value,
                exception.GetType().Name,
                false);
        }
    }

    private HttpRequestMessage CreateCodeunitRequest(
        NavisionPalletOutputJob job,
        string binCode,
        string unitOfMeasure,
        string assemblyLine)
    {
        XNamespace soap = SoapEnvelopeNamespace;
        XNamespace codeunit = CodeunitNamespace;
        var document = new XDocument(
            new XElement(
                soap + "Envelope",
                new XElement(
                    soap + "Body",
                    new XElement(
                        codeunit + "RegistrarSalidaFabricacion",
                        new XElement(codeunit + "n_OP", job.OrderNumber),
                        new XElement(codeunit + "n_Producto", job.ProductNumber),
                        new XElement(codeunit + "n_Lote", job.LotNumber),
                        new XElement(
                            codeunit + "dec_Cdad",
                            job.GoodQuantity.ToString(CultureInfo.InvariantCulture)),
                        new XElement(codeunit + "cod_Ubicacion", binCode),
                        new XElement(codeunit + "unidadMedida", unitOfMeasure),
                        new XElement(codeunit + "userBC", job.EmployeeNumber),
                        new XElement(codeunit + "assemblyLine", assemblyLine)))));
        var request = new HttpRequestMessage(HttpMethod.Post, options.ServiceEndpoint)
        {
            Content = new StringContent(
                document.ToString(SaveOptions.DisableFormatting),
                Encoding.UTF8,
                "text/xml")
        };
        request.Headers.TryAddWithoutValidation(
            "SOAPAction",
            CodeunitNamespace + ":RegistrarSalidaFabricacion");
        return request;
    }

    private HttpRequestMessage CreateIsOpenPalletRequest(
        string orderNumber,
        string assemblyLine)
    {
        XNamespace soap = SoapEnvelopeNamespace;
        XNamespace codeunit = CodeunitNamespace;
        var document = new XDocument(
            new XElement(
                soap + "Envelope",
                new XElement(
                    soap + "Body",
                    new XElement(
                        codeunit + "IsOpenPallet",
                        new XElement(codeunit + "prodOrderNo", orderNumber),
                        new XElement(codeunit + "assemblyLine", assemblyLine)))));
        return CreateSoapRequest(document, "IsOpenPallet");
    }

    private HttpRequestMessage CreateOpenClosePalletRequest(
        NavisionPalletOutputJob job,
        string assemblyLine)
    {
        XNamespace soap = SoapEnvelopeNamespace;
        XNamespace codeunit = CodeunitNamespace;
        var document = new XDocument(
            new XElement(
                soap + "Envelope",
                new XElement(
                    soap + "Body",
                    new XElement(
                        codeunit + "OpenClosePallet",
                        new XElement(codeunit + "productionOrderNo", job.OrderNumber),
                        new XElement(codeunit + "userBC", job.EmployeeNumber),
                        new XElement(codeunit + "itemNo", job.ProductNumber),
                        new XElement(codeunit + "partialQuantity", "0"),
                        new XElement(codeunit + "assemblyLine", assemblyLine)))));
        return CreateSoapRequest(document, "OpenClosePallet");
    }

    private HttpRequestMessage CreateSoapRequest(XDocument document, string operation)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, options.ServiceEndpoint)
        {
            Content = new StringContent(
                document.ToString(SaveOptions.DisableFormatting),
                Encoding.UTF8,
                "text/xml")
        };
        request.Headers.TryAddWithoutValidation(
            "SOAPAction",
            CodeunitNamespace + ":" + operation);
        return request;
    }

    private static async Task<bool?> ReadCodeunitResultAsync(
        HttpResponseMessage response,
        CancellationToken cancellationToken) =>
        await ReadBooleanCodeunitResultAsync(
            response,
            "RegistrarSalidaFabricacion_Result",
            cancellationToken);

    private static async Task<bool?> ReadBooleanCodeunitResultAsync(
        HttpResponseMessage response,
        string resultElement,
        CancellationToken cancellationToken)
    {
        if (response.Content.Headers.ContentLength > MaximumResponseBytes)
            return null;
        try
        {
            var body = await response.Content.ReadAsByteArrayAsync(cancellationToken);
            if (body.Length == 0 || body.Length > MaximumResponseBytes)
                return null;
            using var stream = new MemoryStream(body, writable: false);
            using var reader = XmlReader.Create(
                stream,
                new XmlReaderSettings
                {
                    DtdProcessing = DtdProcessing.Prohibit,
                    XmlResolver = null
                });
            var document = XDocument.Load(reader);
            XNamespace soap = SoapEnvelopeNamespace;
            XNamespace codeunit = CodeunitNamespace;
            if (document.Descendants(soap + "Fault").Any())
                return null;
            var value = document
                .Descendants(codeunit + resultElement)
                .Elements(codeunit + "return_value")
                .SingleOrDefault()?.Value;
            return bool.TryParse(value, out var result) ? result : null;
        }
        catch (Exception exception)
            when (exception is XmlException or InvalidOperationException)
        {
            return null;
        }
    }

    private static async Task<bool> ReadVoidCodeunitResultAsync(
        HttpResponseMessage response,
        string resultElement,
        CancellationToken cancellationToken)
    {
        if (response.Content.Headers.ContentLength > MaximumResponseBytes)
            return false;
        try
        {
            var body = await response.Content.ReadAsByteArrayAsync(cancellationToken);
            if (body.Length == 0 || body.Length > MaximumResponseBytes)
                return false;
            using var stream = new MemoryStream(body, writable: false);
            using var reader = XmlReader.Create(
                stream,
                new XmlReaderSettings
                {
                    DtdProcessing = DtdProcessing.Prohibit,
                    XmlResolver = null
                });
            var document = XDocument.Load(reader);
            XNamespace soap = SoapEnvelopeNamespace;
            XNamespace codeunit = CodeunitNamespace;
            return !document.Descendants(soap + "Fault").Any()
                && document.Descendants(codeunit + resultElement).Count() == 1;
        }
        catch (Exception exception)
            when (exception is XmlException or InvalidOperationException)
        {
            return false;
        }
    }

    private async Task<IReadOnlyList<T>> ReadODataAsync<T>(
        Uri endpoint,
        Func<JsonElement, T> map,
        CancellationToken cancellationToken)
    {
        for (var attempt = 1; attempt <= MaximumReadAttempts; attempt++)
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, endpoint);
            using var timeout =
                CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(options.RequestTimeout);
            try
            {
                using var response = await httpClient.SendAsync(
                    request,
                    HttpCompletionOption.ResponseHeadersRead,
                    timeout.Token);
                var status = (int)response.StatusCode;
                if (!response.IsSuccessStatusCode)
                {
                    var transient = response.StatusCode is HttpStatusCode.RequestTimeout
                        or HttpStatusCode.TooManyRequests
                        || status >= 500;
                    if (transient && attempt < MaximumReadAttempts)
                        continue;
                    throw new NavisionReadException(
                        transient,
                        status,
                        "ODataHttpFailure");
                }

                if (response.Content.Headers.ContentLength > MaximumResponseBytes)
                    throw new NavisionReadException(false, status, "ODataResponseTooLarge");
                var body = await response.Content.ReadAsByteArrayAsync(timeout.Token);
                if (body.Length == 0 || body.Length > MaximumResponseBytes)
                    throw new NavisionReadException(false, status, "ODataResponseInvalid");
                try
                {
                    using var document = JsonDocument.Parse(body);
                    var value = document.RootElement.GetProperty("value");
                    if (value.ValueKind is not JsonValueKind.Array)
                        throw new FormatException();
                    return value.EnumerateArray().Select(map).ToArray();
                }
                catch (Exception exception)
                    when (exception is JsonException or FormatException
                        or InvalidOperationException or OverflowException)
                {
                    throw new NavisionReadException(
                        false,
                        status,
                        "ODataResponseInvalid");
                }
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (OperationCanceledException) when (attempt < MaximumReadAttempts)
            {
                continue;
            }
            catch (OperationCanceledException)
            {
                throw new NavisionReadException(true, null, "ODataTimeout");
            }
            catch (HttpRequestException) when (attempt < MaximumReadAttempts)
            {
                continue;
            }
            catch (HttpRequestException exception)
            {
                throw new NavisionReadException(
                    true,
                    exception.StatusCode is null ? null : (int)exception.StatusCode.Value,
                    "ODataTransportFailure");
            }
        }

        throw new InvalidOperationException("Unreachable OData read state.");
    }

    private Uri CreateODataEndpoint(
        string entity,
        string filter,
        string select,
        int top,
        string? orderBy = null)
    {
        var query = "$filter=" + Uri.EscapeDataString(filter)
            + "&$select=" + select
            + "&$top=" + top.ToString(CultureInfo.InvariantCulture);
        if (orderBy is not null)
            query += "&$orderby=" + Uri.EscapeDataString(orderBy);
        return new Uri(options.ODataCompanyRoot, entity + "?" + query);
    }

    private static string EscapeODataLiteral(string value) =>
        value.Replace("'", "''", StringComparison.Ordinal);

    private static string RequiredString(JsonElement element, string name)
    {
        var value = OptionalString(element, name);
        return string.IsNullOrWhiteSpace(value) ? throw new FormatException() : value;
    }

    private static string OptionalString(JsonElement element, string name) =>
        element.TryGetProperty(name, out var property)
            && property.ValueKind is JsonValueKind.String
            ? property.GetString()?.Trim() ?? string.Empty
            : string.Empty;

    private static int RequiredPositiveInt(JsonElement element, string name)
    {
        if (!element.TryGetProperty(name, out var property)
            || !property.TryGetInt32(out var value)
            || value <= 0)
        {
            throw new FormatException();
        }
        return value;
    }

    private static decimal RequiredDecimal(JsonElement element, string name)
    {
        if (!element.TryGetProperty(name, out var property))
            throw new FormatException();
        if (property.ValueKind is JsonValueKind.Number
            && property.TryGetDecimal(out var numeric))
            return numeric;
        if (property.ValueKind is JsonValueKind.String
            && decimal.TryParse(
                property.GetString(),
                NumberStyles.Number,
                CultureInfo.InvariantCulture,
                out var text))
        {
            return text;
        }
        throw new FormatException();
    }

    private static NavisionPalletOutputReceipt Receipt(
        NavisionPalletOutputDeliveryOutcome outcome,
        int? status,
        string? reason = null,
        string? externalIdentifier = null,
        int? baselineMaximumId = null) =>
        new(
            outcome,
            externalIdentifier,
            status,
            JsonSerializer.Serialize(new
            {
                adapter = nameof(NavisionSoapPalletOutputSender),
                contract = "RegistrarSalidaFabricacion",
                outcome = outcome.ToString(),
                httpStatus = status,
                reason,
                baselineMaximumId
            }));

    private sealed record OrderRecord(
        string OrderNumber,
        string ProductNumber,
        string LotNumber,
        string BinCode);

    private sealed record ProductRecord(string ProductNumber, string UnitOfMeasure);

    private sealed record OutputRecord(
        int Id,
        string OrderNumber,
        string ProductNumber,
        decimal Quantity,
        string State,
        string Type);

    private sealed record SoapAttempt(
        int? HttpStatusCode,
        string? Reason,
        bool IsDefinitiveRejection);

    private sealed record PalletStateTransition(
        bool Succeeded,
        NavisionPalletOutputDeliveryOutcome Outcome,
        int? HttpStatusCode,
        string? Reason)
    {
        public static readonly PalletStateTransition Success = new(
            true,
            NavisionPalletOutputDeliveryOutcome.Confirmed,
            null,
            null);
    }

    private sealed class NavisionReadException(
        bool isTransient,
        int? httpStatusCode,
        string reason) : Exception
    {
        public bool IsTransient { get; } = isTransient;
        public int? HttpStatusCode { get; } = httpStatusCode;
        public string Reason { get; } = reason;
    }
}
