using System.Globalization;
using System.Xml.Linq;
using Ebir.Mes.Application.ProductionOrders;

namespace Ebir.Mes.Integrations.Navision;

public sealed class NavisionProductionOrderSource(
    HttpClient httpClient,
    NavisionOptions options)
    : IProductionOrderSource
{
    public const int MaximumPageSize = 100;
    public const int MaximumOrderNumberLength = 20;

    private static readonly NavisionPage OrdersPage = new(
        "WS_CPP_ProdOrderList",
        "urn:microsoft-dynamics-schemas/page/ws_cpp_prodorderlist");
    private static readonly NavisionPage LinesPage = new(
        "WS_CPP_ProdOrderLineList",
        "urn:microsoft-dynamics-schemas/page/ws_cpp_prodorderlinelist");
    private static readonly NavisionPage ReleasedOrdersPage = new(
        "WS_CPP_OPLanzadas",
        "urn:microsoft-dynamics-schemas/page/ws_cpp_oplanzadas");
    private static readonly NavisionPage ComponentsPage = new(
        "WS_CPP_Componentes",
        "urn:microsoft-dynamics-schemas/page/ws_cpp_componentes");
    private readonly NavisionSoapPageReader reader = new(httpClient, options);
    private readonly NavisionODataRoutingReader routingReader = new(
        httpClient,
        options);
    private readonly NavisionODataV4PalletFormatReader palletFormatReader = new(
        httpClient,
        options);
    private readonly NavisionODataV4ProductPostingGroupReader productPostingGroupReader =
        new(httpClient, options);

    public async Task<IReadOnlyList<ProductionOrderRecord>> ReadAsync(
        ProductionOrderStatus status,
        int maximumRecords,
        CancellationToken cancellationToken)
    {
        ValidatePageSize(maximumRecords);
        var document = await reader.ReadMultipleAsync(
            OrdersPage,
            [new NavisionFilter("Status", ToNavisionStatus(status))],
            maximumRecords,
            cancellationToken);
        return MapRecords(document, OrdersPage, MapOrder);
    }

    public async Task<ProductionOrderRecord?> ReadOrderAsync(
        ProductionOrderStatus status,
        string orderNumber,
        CancellationToken cancellationToken)
    {
        var normalizedOrderNumber = NormalizeOrderNumber(orderNumber);
        var document = await reader.ReadMultipleAsync(
            OrdersPage,
            [
                new NavisionFilter("Status", ToNavisionStatus(status)),
                new NavisionFilter("No", normalizedOrderNumber)
            ],
            2,
            cancellationToken);
        var records = MapRecords(document, OrdersPage, MapOrder);
        return records.Count switch
        {
            0 => null,
            1 => records[0],
            _ => throw new ProductionOrderSourceUnavailableException(
                "NAV returned more than one production order for an exact key.")
        };
    }

    public async Task<IReadOnlyList<ProductionOrderLineRecord>> ReadLinesAsync(
        ProductionOrderStatus status,
        string orderNumber,
        int maximumRecords,
        CancellationToken cancellationToken)
    {
        ValidatePageSize(maximumRecords);
        var normalizedOrderNumber = NormalizeOrderNumber(orderNumber);
        var document = await reader.ReadMultipleAsync(
            LinesPage,
            [
                new NavisionFilter("Status", ToNavisionStatus(status)),
                new NavisionFilter("Prod_Order_No", normalizedOrderNumber)
            ],
            maximumRecords,
            cancellationToken);
        return MapRecords(document, LinesPage, MapLine);
    }

    public async Task<ProductionOrderLotRecord?> ReadLotAsync(
        string orderNumber,
        CancellationToken cancellationToken)
    {
        var normalizedOrderNumber = NormalizeOrderNumber(orderNumber);
        var document = await reader.ReadMultipleAsync(
            ReleasedOrdersPage,
            [new NavisionFilter("No", normalizedOrderNumber)],
            2,
            cancellationToken);
        var records = MapRecords(document, ReleasedOrdersPage, MapLot);
        return records.Count switch
        {
            0 => null,
            1 => records[0],
            _ => throw new ProductionOrderSourceUnavailableException(
                "NAV returned more than one output lot for an exact production order key.")
        };
    }

    public async Task<IReadOnlyList<ProductionOrderRoutingStepRecord>>
        ReadRoutingAsync(
            string orderNumber,
            int maximumRecords,
            CancellationToken cancellationToken)
    {
        ValidatePageSize(maximumRecords);
        var normalizedOrderNumber = NormalizeOrderNumber(orderNumber);
        return await routingReader.ReadAsync(
            normalizedOrderNumber, maximumRecords, cancellationToken);
    }

    public async Task<IReadOnlyList<ProductionOrderComponentRecord>>
        ReadComponentsAsync(
            ProductionOrderStatus status,
            string orderNumber,
            int maximumRecords,
            CancellationToken cancellationToken)
    {
        ValidatePageSize(maximumRecords);
        var normalizedOrderNumber = NormalizeOrderNumber(orderNumber);
        var document = await reader.ReadMultipleAsync(
            ComponentsPage,
            [
                new NavisionFilter("Status", ToNavisionStatus(status)),
                new NavisionFilter("Prod_Order_No", normalizedOrderNumber)
            ],
            maximumRecords,
            cancellationToken);
        return MapRecords(document, ComponentsPage, MapComponent);
    }

    public async Task<IReadOnlyList<ProductionOrderPalletFormatRecord>>
        ReadPalletFormatsAsync(
            string productNumber,
            string formatCode,
            int maximumRecords,
            CancellationToken cancellationToken)
    {
        ValidatePageSize(maximumRecords);
        var normalizedProductNumber = NormalizeExactFilter(
            productNumber,
            50,
            nameof(productNumber));
        var normalizedFormatCode = NormalizeExactFilter(
            formatCode,
            50,
            nameof(formatCode));
        return await palletFormatReader.ReadAsync(
            normalizedProductNumber,
            normalizedFormatCode,
            maximumRecords,
            cancellationToken);
    }

    public async Task<IReadOnlyList<ProductionOrderProductPostingGroupRecord>>
        ReadProductPostingGroupsAsync(
            string productNumber,
            int maximumRecords,
            CancellationToken cancellationToken)
    {
        ValidatePageSize(maximumRecords);
        var normalizedProductNumber = NormalizeExactFilter(
            productNumber,
            50,
            nameof(productNumber));
        return await productPostingGroupReader.ReadAsync(
            normalizedProductNumber,
            maximumRecords,
            cancellationToken);
    }

    private static IReadOnlyList<T> MapRecords<T>(
        XDocument document,
        NavisionPage page,
        Func<XElement, XNamespace, T> mapper)
    {
        try
        {
            XNamespace pageNamespace = page.Namespace;
            return document
                .Descendants(pageNamespace + page.Name)
                .Select(record => mapper(record, pageNamespace))
                .ToArray();
        }
        catch (Exception exception)
            when (exception is FormatException or OverflowException)
        {
            throw new ProductionOrderSourceUnavailableException(
                "NAV returned an invalid production order response.",
                exception);
        }
    }

    private static ProductionOrderRecord MapOrder(
        XElement record,
        XNamespace page)
    {
        var orderNumber = RequiredValue(record, page + "No");
        var status = ParseStatus(RequiredValue(record, page + "Status"));

        return new ProductionOrderRecord(
            orderNumber,
            status,
            Value(record, page + "Description"),
            Value(record, page + "Source_No"),
            Value(record, page + "Routing_No"),
            ParseDecimal(Value(record, page + "Quantity")),
            Value(record, page + "Location_Code"),
            ParseDate(Value(record, page + "Starting_Date")),
            ParseDate(Value(record, page + "Ending_Date")),
            ParseDate(Value(record, page + "Due_Date")));
    }

    private static ProductionOrderLineRecord MapLine(
        XElement record,
        XNamespace page)
    {
        return new ProductionOrderLineRecord(
            RequiredValue(record, page + "Prod_Order_No"),
            ParseStatus(RequiredValue(record, page + "Status")),
            RequiredValue(record, page + "Item_No"),
            Value(record, page + "Variant_Code"),
            Value(record, page + "Description"),
            Value(record, page + "Location_Code"),
            ParseDecimal(Value(record, page + "Quantity")),
            ParseDecimal(Value(record, page + "Finished_Quantity")),
            ParseDecimal(Value(record, page + "Remaining_Quantity")),
            ParseDecimal(Value(record, page + "Scrap_Percent")),
            ParseDate(Value(record, page + "Due_Date")),
            ParseDate(Value(record, page + "Starting_Date")),
            ParseDate(Value(record, page + "Ending_Date")),
            Value(record, page + "Production_BOM_No"));
    }

    private static ProductionOrderLotRecord MapLot(
        XElement record,
        XNamespace page) =>
        new(
            RequiredValue(record, page + "No"),
            RequiredValue(record, page + "Source_No"),
            Value(record, page + "Cód_Lote_Salida"));

    private static ProductionOrderComponentRecord MapComponent(
        XElement record,
        XNamespace page)
    {
        return new ProductionOrderComponentRecord(
            RequiredValue(record, page + "Prod_Order_No"),
            ParseInt(RequiredValue(record, page + "Prod_Order_Line_No")),
            ParseInt(RequiredValue(record, page + "Line_No")),
            ParseStatus(RequiredValue(record, page + "Status")),
            RequiredValue(record, page + "Item_No"),
            Value(record, page + "Variant_Code"),
            Value(record, page + "Description"),
            ParseDecimal(Value(record, page + "Quantity_per")),
            ParseDecimal(Value(record, page + "Expected_Quantity")),
            ParseDecimal(Value(record, page + "Remaining_Quantity")),
            ParseDecimal(Value(record, page + "Act_Consumption_Qty")),
            Value(record, page + "Unit_of_Measure_Code"),
            ParseFlushingMethod(RequiredValue(record, page + "Flushing_Method")),
            Value(record, page + "Routing_Link_Code"),
            Value(record, page + "Cod_Operacion"),
            Value(record, page + "Location_Code"),
            Value(record, page + "Bin_Code"),
            ParseDecimal(Value(record, page + "Qty_Picked")),
            ParseBool(Value(record, page + "Substitution_Available")));
    }

    private static string NormalizeOrderNumber(string orderNumber)
    {
        ArgumentNullException.ThrowIfNull(orderNumber);
        var normalized = orderNumber.Trim().ToUpperInvariant();
        if (normalized.Length == 0 ||
            normalized.Length > MaximumOrderNumberLength)
        {
            throw new ArgumentOutOfRangeException(
                nameof(orderNumber),
                $"The NAV order number must contain between 1 and {MaximumOrderNumberLength} characters.");
        }

        if (normalized.Contains("..", StringComparison.Ordinal) ||
            normalized.Any(character =>
                !char.IsLetterOrDigit(character) &&
                character is not '-' and not '/' and not '_' and not '.'))
        {
            throw new ArgumentException(
                "The NAV order number contains filter control characters.",
                nameof(orderNumber));
        }

        return normalized;
    }

    private static string NormalizeExactFilter(
        string value,
        int maximumLength,
        string parameterName)
    {
        ArgumentNullException.ThrowIfNull(value);
        var normalized = value.Trim().ToUpperInvariant();
        if (normalized.Length == 0 || normalized.Length > maximumLength)
        {
            throw new ArgumentOutOfRangeException(
                parameterName,
                $"The NAV filter must contain between 1 and {maximumLength} characters.");
        }

        if (normalized.Contains("..", StringComparison.Ordinal) ||
            normalized.Any(character =>
                !char.IsLetterOrDigit(character) &&
                character is not '-' and not '/' and not '_' and not '.'))
        {
            throw new ArgumentException(
                "The NAV filter contains control characters.",
                parameterName);
        }

        return normalized;
    }

    private static void ValidatePageSize(int maximumRecords)
    {
        if (maximumRecords < 1 || maximumRecords > MaximumPageSize)
        {
            throw new ArgumentOutOfRangeException(
                nameof(maximumRecords),
                $"The NAV page size must be between 1 and {MaximumPageSize}.");
        }
    }

    private static string RequiredValue(XElement record, XName name)
    {
        var value = Value(record, name);
        return string.IsNullOrWhiteSpace(value)
            ? throw new FormatException($"NAV response is missing {name.LocalName}.")
            : value;
    }

    private static string Value(XElement record, XName name) =>
        record.Element(name)?.Value.Trim() ?? string.Empty;

    private static decimal ParseDecimal(string value) =>
        string.IsNullOrWhiteSpace(value)
            ? 0m
            : decimal.Parse(value, NumberStyles.Number, CultureInfo.InvariantCulture);

    private static int ParseInt(string value) =>
        int.Parse(value, NumberStyles.Integer, CultureInfo.InvariantCulture);

    private static bool ParseBool(string value) =>
        !string.IsNullOrWhiteSpace(value) && bool.Parse(value);

    private static DateOnly? ParseDate(string value) =>
        string.IsNullOrWhiteSpace(value)
            ? null
            : DateOnly.ParseExact(value, "yyyy-MM-dd", CultureInfo.InvariantCulture);

    private static DateTime? ParseDateTime(string value) =>
        string.IsNullOrWhiteSpace(value)
            ? null
            : DateTime.Parse(
                value,
                CultureInfo.InvariantCulture,
                DateTimeStyles.RoundtripKind);

    private static ProductionOrderStatus ParseStatus(string value) =>
        value switch
        {
            "Simulated" => ProductionOrderStatus.Simulated,
            "Planned" => ProductionOrderStatus.Planned,
            "Firm_Planned" => ProductionOrderStatus.FirmPlanned,
            "Released" => ProductionOrderStatus.Released,
            "Finished" => ProductionOrderStatus.Finished,
            _ => throw new FormatException(
                $"Unknown NAV production order status: {value}.")
        };

    private static string ToNavisionStatus(ProductionOrderStatus status) =>
        status switch
        {
            ProductionOrderStatus.Simulated => "Simulated",
            ProductionOrderStatus.Planned => "Planned",
            ProductionOrderStatus.FirmPlanned => "Firm_Planned",
            ProductionOrderStatus.Released => "Released",
            ProductionOrderStatus.Finished => "Finished",
            _ => throw new ArgumentOutOfRangeException(nameof(status))
        };

    private static ProductionComponentFlushingMethod ParseFlushingMethod(
        string value) =>
        value switch
        {
            "Manual" => ProductionComponentFlushingMethod.Manual,
            "Forward" => ProductionComponentFlushingMethod.Forward,
            "Backward" => ProductionComponentFlushingMethod.Backward,
            "Pick__x002B__Forward" =>
                ProductionComponentFlushingMethod.PickAndForward,
            "Pick__x002B__Backward" =>
                ProductionComponentFlushingMethod.PickAndBackward,
            _ => throw new FormatException(
                $"Unknown NAV component flushing method: {value}.")
        };
}
