using System.Diagnostics;
using System.Net;
using System.Text.Json;
using Ebir.Mes.Application.ProductionOrders;

namespace Ebir.Mes.Integrations.Navision;

internal sealed class NavisionODataV4ProductPostingGroupReader(
    HttpClient httpClient,
    NavisionOptions options)
{
    private const string Entity = "ItemSalesAndProfit";
    private static readonly ActivitySource ActivitySource =
        new("Ebir.Mes.Integrations.Navision");

    public async Task<IReadOnlyList<ProductionOrderProductPostingGroupRecord>>
        ReadAsync(
            string productNumber,
            int maximumRecords,
            CancellationToken cancellationToken)
    {
        using var activity = ActivitySource.StartActivity(
            "navision.product-posting-group.read-odatav4",
            ActivityKind.Client);
        activity?.SetTag("navision.entity", Entity);
        activity?.SetTag("navision.company", options.Company);
        activity?.SetTag("navision.maximum_records", maximumRecords);

        var endpoint = CreateEndpoint(productNumber, maximumRecords);
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
                    $"NAV rejected the product posting group query (HTTP {(int)response.StatusCode}).");
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
                    "NAV did not answer the product posting group query within the configured timeout.",
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
                    "NAV product posting group data is currently unavailable.",
                    exception);
            }
        }

        throw new UnreachableException();
    }

    private Uri CreateEndpoint(string productNumber, int maximumRecords)
    {
        var serviceRoot = options.ServiceRoot;
        const string soapSuffix = "/WS/";
        if (!serviceRoot.AbsolutePath.EndsWith(
                soapSuffix,
                StringComparison.OrdinalIgnoreCase))
        {
            throw new ProductionOrderSourceUnavailableException(
                "NAV service root is not valid for the product posting group query.");
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
                "NAV service root changed authority while building the product posting group query.");
        }

        var company = Uri.EscapeDataString(EscapeLiteral(options.Company));
        var filter = Uri.EscapeDataString(
            $"No eq '{EscapeLiteral(productNumber)}'");
        return new Uri(
            odataRoot,
            $"Company('{company}')/{Entity}?$filter={filter}&$select=No,Gen_Prod_Posting_Group&$top={maximumRecords}");
    }

    private static string EscapeLiteral(string value) =>
        value.Replace("'", "''", StringComparison.Ordinal);

    private static IReadOnlyList<ProductionOrderProductPostingGroupRecord> Parse(
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
            when (exception is JsonException or FormatException or
                InvalidOperationException or KeyNotFoundException)
        {
            throw new ProductionOrderSourceUnavailableException(
                "NAV returned an invalid product posting group response.",
                exception);
        }
    }

    private static ProductionOrderProductPostingGroupRecord MapRecord(
        JsonElement record) =>
        new(
            RequiredString(record, "No"),
            RequiredString(record, "Gen_Prod_Posting_Group"));

    private static string RequiredString(JsonElement record, string name)
    {
        var value = record.GetProperty(name).GetString()?.Trim() ?? string.Empty;
        return value.Length == 0
            ? throw new FormatException($"The product posting group is missing {name}.")
            : value;
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
