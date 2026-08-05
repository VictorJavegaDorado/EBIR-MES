using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Text.Json;
using Ebir.Mes.Application.ProductionOrders;

namespace Ebir.Mes.Integrations.Navision;

internal sealed class NavisionODataV4PalletFormatReader(
    HttpClient httpClient,
    NavisionOptions options)
{
    private const string Entity = "WS_CPP_UndMedProd";
    private static readonly ActivitySource ActivitySource =
        new("Ebir.Mes.Integrations.Navision");

    public async Task<IReadOnlyList<ProductionOrderPalletFormatRecord>> ReadAsync(
        string productNumber,
        string formatCode,
        int maximumRecords,
        CancellationToken cancellationToken)
    {
        using var activity = ActivitySource.StartActivity(
            "navision.pallet-format.read-odatav4",
            ActivityKind.Client);
        activity?.SetTag("navision.entity", Entity);
        activity?.SetTag("navision.company", options.Company);
        activity?.SetTag("navision.maximum_records", maximumRecords);

        var endpoint = CreateEndpoint(productNumber, formatCode, maximumRecords);
        for (var attempt = 1; attempt <= options.MaximumReadAttempts; attempt++)
        {
            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Get, endpoint);
                request.Headers.Accept.ParseAdd("application/json");
                using var timeoutSource =
                    CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                timeoutSource.CancelAfter(options.RequestTimeout);
                using var response = await httpClient.SendAsync(
                    request,
                    HttpCompletionOption.ResponseHeadersRead,
                    timeoutSource.Token);

                if (response.IsSuccessStatusCode)
                {
                    var body = await response.Content.ReadAsStringAsync(timeoutSource.Token);
                    var records = Parse(body);
                    activity?.SetTag("navision.record_count", records.Count);
                    return records;
                }

                if (IsTransient(response.StatusCode) &&
                    attempt < options.MaximumReadAttempts)
                {
                    AddRetryEvent(activity, attempt, response.StatusCode);
                    await DelayBeforeRetryAsync(attempt, cancellationToken);
                    continue;
                }

                throw new ProductionOrderSourceUnavailableException(
                    $"NAV rejected the pallet format query (HTTP {(int)response.StatusCode}).");
            }
            catch (OperationCanceledException exception)
                when (!cancellationToken.IsCancellationRequested)
            {
                if (attempt < options.MaximumReadAttempts)
                {
                    await DelayBeforeRetryAsync(attempt, cancellationToken);
                    continue;
                }

                throw new ProductionOrderSourceUnavailableException(
                    "NAV did not answer the pallet format query within the configured timeout.",
                    exception);
            }
            catch (HttpRequestException exception)
            {
                if (attempt < options.MaximumReadAttempts)
                {
                    await DelayBeforeRetryAsync(attempt, cancellationToken);
                    continue;
                }

                throw new ProductionOrderSourceUnavailableException(
                    "NAV pallet format data is currently unavailable.",
                    exception);
            }
        }

        throw new UnreachableException();
    }

    private Uri CreateEndpoint(
        string productNumber,
        string formatCode,
        int maximumRecords)
    {
        var serviceRoot = options.ServiceRoot;
        const string soapSuffix = "/WS/";
        if (!serviceRoot.AbsolutePath.EndsWith(
                soapSuffix,
                StringComparison.OrdinalIgnoreCase))
        {
            throw new ProductionOrderSourceUnavailableException(
                "NAV service root is not valid for the pallet format query.");
        }

        var rootBuilder = new UriBuilder(serviceRoot)
        {
            Path = serviceRoot.AbsolutePath[..^soapSuffix.Length] + "/ODataV4/",
            Query = string.Empty,
            Fragment = string.Empty
        };
        var odataRoot = rootBuilder.Uri;
        if (!string.Equals(odataRoot.Scheme, serviceRoot.Scheme, StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(odataRoot.Host, serviceRoot.Host, StringComparison.OrdinalIgnoreCase) ||
            odataRoot.Port != serviceRoot.Port)
        {
            throw new ProductionOrderSourceUnavailableException(
                "NAV service root changed authority while building the pallet format query.");
        }

        var company = Uri.EscapeDataString(EscapeLiteral(options.Company));
        var filter = Uri.EscapeDataString(
            $"Item_No eq '{EscapeLiteral(productNumber)}' and Code eq '{EscapeLiteral(formatCode)}'");
        return new Uri(
            odataRoot,
            $"Company('{company}')/{Entity}?$filter={filter}&$top={maximumRecords}");
    }

    private static string EscapeLiteral(string value) =>
        value.Replace("'", "''", StringComparison.Ordinal);

    private static IReadOnlyList<ProductionOrderPalletFormatRecord> Parse(
        string responseBody)
    {
        try
        {
            using var document = JsonDocument.Parse(responseBody);
            var values = document.RootElement.GetProperty("value");
            if (values.ValueKind != JsonValueKind.Array)
            {
                throw new FormatException("The OData V4 value is not an array.");
            }

            return values.EnumerateArray().Select(MapRecord).ToArray();
        }
        catch (Exception exception)
            when (exception is JsonException or FormatException or OverflowException or
                InvalidOperationException or KeyNotFoundException)
        {
            throw new ProductionOrderSourceUnavailableException(
                "NAV returned an invalid pallet format response.",
                exception);
        }
    }

    private static ProductionOrderPalletFormatRecord MapRecord(JsonElement record) =>
        new(
            RequiredString(record, "Item_No"),
            RequiredString(record, "Code"),
            ReadDecimal(record, "Qty_per_Unit_of_Measure"));

    private static string RequiredString(JsonElement record, string name)
    {
        var value = record.GetProperty(name).GetString()?.Trim() ?? string.Empty;
        return value.Length == 0
            ? throw new FormatException($"The pallet format is missing {name}.")
            : value;
    }

    private static decimal ReadDecimal(JsonElement record, string name)
    {
        var value = record.GetProperty(name);
        return value.ValueKind switch
        {
            JsonValueKind.Number => value.GetDecimal(),
            JsonValueKind.String => decimal.Parse(
                value.GetString() ?? string.Empty,
                NumberStyles.Number,
                CultureInfo.InvariantCulture),
            _ => throw new FormatException($"The pallet format has an invalid {name}.")
        };
    }

    private static bool IsTransient(HttpStatusCode statusCode) =>
        statusCode is HttpStatusCode.RequestTimeout or
            HttpStatusCode.TooManyRequests ||
        (int)statusCode >= 500;

    private static void AddRetryEvent(
        Activity? activity,
        int attempt,
        HttpStatusCode statusCode) =>
        activity?.AddEvent(new ActivityEvent(
            "navision.read.retry",
            tags: new ActivityTagsCollection
            {
                ["attempt"] = attempt,
                ["http.status_code"] = (int)statusCode
            }));

    private static Task DelayBeforeRetryAsync(
        int attempt,
        CancellationToken cancellationToken) =>
        Task.Delay(TimeSpan.FromMilliseconds(100 * attempt), cancellationToken);
}
