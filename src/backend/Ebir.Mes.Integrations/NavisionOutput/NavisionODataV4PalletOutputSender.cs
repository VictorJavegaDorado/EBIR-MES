using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Ebir.Mes.Application.NavisionOutput;

namespace Ebir.Mes.Integrations.NavisionOutput;

public sealed class NavisionODataV4PalletOutputSender(
    HttpClient httpClient,
    NavisionPalletOutputOptions options) : INavisionPalletOutputSender
{
    private const int MaximumResponseBytes = 64 * 1024;
    private static readonly JsonSerializerOptions RequestJsonOptions =
        new(JsonSerializerDefaults.General);

    public async Task<NavisionPalletOutputReceipt> SendAsync(
        NavisionPalletOutputJob job,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, options.ServiceEndpoint)
        {
            Content = JsonContent.Create(
                new
                {
                    Orden = job.OrderNumber,
                    Producto = job.ProductNumber,
                    Cantidad_salida = job.GoodQuantity,
                    fecha = job.ClosedAtUtc.UtcDateTime,
                    Tipo = "Salida"
                },
                options: RequestJsonOptions)
        };
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(options.RequestTimeout);
        try
        {
            using var response = await httpClient.SendAsync(
                request,
                HttpCompletionOption.ResponseHeadersRead,
                timeout.Token);

            if (response.StatusCode is HttpStatusCode.Created or HttpStatusCode.OK)
                return await ReadConfirmationAsync(job, response, timeout.Token);

            var status = (int)response.StatusCode;
            var outcome = response.StatusCode is HttpStatusCode.RequestTimeout
                or HttpStatusCode.TooManyRequests
                || status >= 500
                ? NavisionPalletOutputDeliveryOutcome.UnknownResult
                : NavisionPalletOutputDeliveryOutcome.PermanentFailure;
            return Receipt(outcome, status);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (OperationCanceledException exception)
        {
            return Receipt(
                NavisionPalletOutputDeliveryOutcome.UnknownResult,
                null,
                exception.GetType().Name);
        }
        catch (HttpRequestException exception)
        {
            return Receipt(
                NavisionPalletOutputDeliveryOutcome.UnknownResult,
                exception.StatusCode is null ? null : (int)exception.StatusCode.Value,
                exception.GetType().Name);
        }
    }

    private static async Task<NavisionPalletOutputReceipt> ReadConfirmationAsync(
        NavisionPalletOutputJob job,
        HttpResponseMessage response,
        CancellationToken cancellationToken)
    {
        var status = (int)response.StatusCode;
        if (response.Content.Headers.ContentLength > MaximumResponseBytes)
            return Receipt(NavisionPalletOutputDeliveryOutcome.UnknownResult, status);

        byte[] body;
        try
        {
            body = await response.Content.ReadAsByteArrayAsync(cancellationToken);
            if (body.Length == 0 || body.Length > MaximumResponseBytes)
                return Receipt(NavisionPalletOutputDeliveryOutcome.UnknownResult, status);

            using var document = JsonDocument.Parse(body, new JsonDocumentOptions
            {
                MaxDepth = 16
            });
            var root = document.RootElement;
            if (!TryReadPositiveId(root, out var id)
                || !MatchesString(root, "Orden", job.OrderNumber)
                || !MatchesString(root, "Producto", job.ProductNumber)
                || !MatchesQuantity(root, job.GoodQuantity)
                || !MatchesString(root, "Tipo", "Salida"))
            {
                return Receipt(NavisionPalletOutputDeliveryOutcome.UnknownResult, status);
            }

            var externalIdentifier = id.ToString(CultureInfo.InvariantCulture);
            if (!root.TryGetProperty("Estado", out var state)
                || state.ValueKind != JsonValueKind.String)
            {
                return Receipt(
                    NavisionPalletOutputDeliveryOutcome.UnknownResult,
                    status,
                    externalIdentifier: externalIdentifier);
            }

            return state.GetString() switch
            {
                "Registrado" => Receipt(
                    NavisionPalletOutputDeliveryOutcome.Confirmed,
                    status,
                    externalIdentifier: externalIdentifier),
                "Error" => Receipt(
                    NavisionPalletOutputDeliveryOutcome.PermanentFailure,
                    status,
                    externalIdentifier: externalIdentifier),
                _ => Receipt(
                    NavisionPalletOutputDeliveryOutcome.UnknownResult,
                    status,
                    externalIdentifier: externalIdentifier)
            };
        }
        catch (JsonException exception)
        {
            return Receipt(
                NavisionPalletOutputDeliveryOutcome.UnknownResult,
                status,
                exception.GetType().Name);
        }
    }

    private static bool TryReadPositiveId(JsonElement root, out int id)
    {
        id = 0;
        return root.TryGetProperty("Id", out var property)
            && property.TryGetInt32(out id)
            && id > 0;
    }

    private static bool MatchesString(
        JsonElement root,
        string propertyName,
        string expected) =>
        root.TryGetProperty(propertyName, out var property)
        && string.Equals(property.GetString(), expected, StringComparison.Ordinal);

    private static bool MatchesQuantity(
        JsonElement root,
        int expected) =>
        root.TryGetProperty("Cantidad_salida", out var property)
        && property.TryGetDecimal(out var value)
        && value == expected;

    private static NavisionPalletOutputReceipt Receipt(
        NavisionPalletOutputDeliveryOutcome outcome,
        int? status,
        string? exception = null,
        string? externalIdentifier = null) =>
        new(
            outcome,
            externalIdentifier,
            status,
            JsonSerializer.Serialize(new
            {
                adapter = nameof(NavisionODataV4PalletOutputSender),
                outcome = outcome.ToString(),
                httpStatus = status,
                exception
            }));
}
