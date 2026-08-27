using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using ZXing;
using ZXing.Common;

namespace Ebir.Mes.Integrations.Printing;

internal static class PalletLabelRenderer
{
    private const float WidthMillimetres = 150f;
    private const float HeightMillimetres = 100f;
    private const string LogoResourceName =
        "Ebir.Mes.Integrations.Printing.Assets.ebir-logo-mono.png";

    public static void Draw(Graphics graphics, PalletLabelContent label)
    {
        ArgumentNullException.ThrowIfNull(graphics);
        ArgumentNullException.ThrowIfNull(label);

        var previousUnit = graphics.PageUnit;
        var previousSmoothing = graphics.SmoothingMode;
        var previousInterpolation = graphics.InterpolationMode;
        graphics.PageUnit = GraphicsUnit.Millimeter;
        graphics.SmoothingMode = SmoothingMode.HighQuality;
        graphics.InterpolationMode = InterpolationMode.NearestNeighbor;
        graphics.Clear(Color.White);

        using var borderPen = new Pen(Color.Black, 0.6f);
        using var dividerPen = new Pen(Color.Black, 0.35f);
        using var headingFont = new Font(FontFamily.GenericSansSerif, 8f, FontStyle.Bold, GraphicsUnit.Point);
        using var valueFont = new Font(FontFamily.GenericSansSerif, 9f, FontStyle.Regular, GraphicsUnit.Point);
        using var descriptionFont = new Font(FontFamily.GenericSansSerif, 10f, FontStyle.Bold, GraphicsUnit.Point);
        using var quantityFont = new Font(FontFamily.GenericSansSerif, 22f, FontStyle.Bold, GraphicsUnit.Point);
        using var barcodeTextFont = new Font(FontFamily.GenericSansSerif, 7f, FontStyle.Regular, GraphicsUnit.Point);
        using var brush = new SolidBrush(Color.Black);
        using var centered = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
        using var rightAligned = new StringFormat { Alignment = StringAlignment.Far, Trimming = StringTrimming.EllipsisCharacter };
        using var ellipsisWord = new StringFormat { Trimming = StringTrimming.EllipsisWord };
        using var ellipsisCharacter = new StringFormat { Trimming = StringTrimming.EllipsisCharacter };

        graphics.DrawRectangle(borderPen, 2f, 2f, WidthMillimetres - 4f, HeightMillimetres - 4f);
        DrawLogo(graphics, new RectangleF(5f, 4f, 28f, 14f));
        DrawCode128(graphics, label.ProductCode, new RectangleF(38f, 4f, 72f, 11f));
        graphics.DrawString(label.ProductCode, barcodeTextFont, brush, new RectangleF(38f, 15f, 72f, 4f), centered);
        graphics.DrawString(label.ProductPostingGroup, headingFont, brush, new RectangleF(113f, 6f, 31f, 10f), rightAligned);
        graphics.DrawLine(dividerPen, 4f, 20f, 146f, 20f);

        graphics.DrawString(
            $"{label.ProductCode} - {label.ProductDescription}",
            descriptionFont,
            brush,
            new RectangleF(6f, 22f, 138f, 12f),
            ellipsisWord);

        DrawField(graphics, brush, headingFont, valueFont, "ORDEN", label.ProductionOrderNumber, 6f, 35f, 43f);
        DrawField(graphics, brush, headingFont, valueFont, "LOTE", label.Lot, 52f, 35f, 43f);
        DrawField(graphics, brush, headingFont, valueFont, "LINEA", label.AssemblyLineName, 98f, 35f, 46f);

        graphics.DrawLine(dividerPen, 4f, 51f, 146f, 51f);
        graphics.DrawString("CANTIDAD", headingFont, brush, 6f, 53f);
        var quantity = label.Quantity.ToString("0.###", CultureInfo.InvariantCulture);
        graphics.DrawString(quantity, quantityFont, brush, new RectangleF(5f, 58f, 42f, 15f), ellipsisCharacter);
        DrawCode128(graphics, quantity, new RectangleF(50f, 54f, 38f, 12f));
        graphics.DrawString(quantity, barcodeTextFont, brush, new RectangleF(50f, 66f, 38f, 4f), centered);

        var legacyProductScan = string.Concat(label.ProductCode, ";");
        DrawCode128(graphics, legacyProductScan, new RectangleF(92f, 54f, 52f, 12f));
        graphics.DrawString(legacyProductScan, barcodeTextFont, brush, new RectangleF(92f, 66f, 52f, 4f), centered);

        graphics.DrawLine(dividerPen, 4f, 72f, 146f, 72f);
        graphics.DrawString("PALET", headingFont, brush, 6f, 74f);
        DrawCode128(graphics, label.PalletCode, new RectangleF(23f, 74f, 121f, 14f));
        graphics.DrawString(label.PalletCode, barcodeTextFont, brush, new RectangleF(6f, 89f, 138f, 5f), centered);

        graphics.PageUnit = previousUnit;
        graphics.SmoothingMode = previousSmoothing;
        graphics.InterpolationMode = previousInterpolation;
    }

    internal static BitMatrix EncodeCode128(string value, int width)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value);
        if (width <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(width));
        }

        return new MultiFormatWriter().encode(
            value,
            BarcodeFormat.CODE_128,
            width,
            1,
            new Dictionary<EncodeHintType, object>
            {
                [EncodeHintType.MARGIN] = 0,
                [EncodeHintType.FORCE_CODE_SET] = "B"
            });
    }

    private static void DrawCode128(Graphics graphics, string value, RectangleF bounds)
    {
        const float quietZoneMillimetres = 2f;
        var bars = RectangleF.FromLTRB(
            bounds.Left + quietZoneMillimetres,
            bounds.Top,
            bounds.Right - quietZoneMillimetres,
            bounds.Bottom);
        var matrix = EncodeCode128(value, Math.Max(1, (int)MathF.Round(bars.Width * 8f)));
        var columnWidth = bars.Width / matrix.Width;

        var start = -1;
        for (var x = 0; x <= matrix.Width; x++)
        {
            var black = x < matrix.Width && matrix[x, 0];
            if (black && start < 0)
            {
                start = x;
            }
            else if (!black && start >= 0)
            {
                graphics.FillRectangle(
                    Brushes.Black,
                    bars.Left + (start * columnWidth),
                    bars.Top,
                    (x - start) * columnWidth,
                    bars.Height);
                start = -1;
            }
        }
    }

    private static void DrawLogo(Graphics graphics, RectangleF bounds)
    {
        using var stream = typeof(PalletLabelRenderer).Assembly.GetManifestResourceStream(LogoResourceName)
            ?? throw new InvalidOperationException($"No se encontro el recurso {LogoResourceName}.");
        using var logo = Image.FromStream(stream);
        graphics.DrawImage(logo, bounds);
    }

    private static void DrawField(
        Graphics graphics,
        Brush brush,
        Font headingFont,
        Font valueFont,
        string heading,
        string value,
        float x,
        float y,
        float width)
    {
        graphics.DrawString(heading, headingFont, brush, x, y);
        using var format = new StringFormat { Trimming = StringTrimming.EllipsisCharacter };
        graphics.DrawString(value, valueFont, brush, new RectangleF(x, y + 6f, width, 8f), format);
    }
}
