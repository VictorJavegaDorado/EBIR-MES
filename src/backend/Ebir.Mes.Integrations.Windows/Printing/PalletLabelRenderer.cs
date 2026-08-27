using System.Drawing;
using System.Drawing.Drawing2D;

namespace Ebir.Mes.Integrations.Printing;

internal static class PalletLabelRenderer
{
    private const float WidthMillimetres = 150f;
    private const float HeightMillimetres = 100f;

    public static void Draw(Graphics graphics, PalletLabelContent label)
    {
        ArgumentNullException.ThrowIfNull(graphics);
        ArgumentNullException.ThrowIfNull(label);

        var previousUnit = graphics.PageUnit;
        var previousSmoothing = graphics.SmoothingMode;
        graphics.PageUnit = GraphicsUnit.Millimeter;
        graphics.SmoothingMode = SmoothingMode.HighQuality;
        graphics.Clear(Color.White);

        using var borderPen = new Pen(Color.Black, 0.6f);
        using var dividerPen = new Pen(Color.Black, 0.35f);
        using var brandFont = new Font(FontFamily.GenericSansSerif, 18f, FontStyle.Bold, GraphicsUnit.Point);
        using var headingFont = new Font(FontFamily.GenericSansSerif, 10f, FontStyle.Bold, GraphicsUnit.Point);
        using var valueFont = new Font(FontFamily.GenericSansSerif, 10f, FontStyle.Regular, GraphicsUnit.Point);
        using var mainCodeFont = new Font(FontFamily.GenericSansSerif, 16f, FontStyle.Bold, GraphicsUnit.Point);
        using var quantityFont = new Font(FontFamily.GenericSansSerif, 24f, FontStyle.Bold, GraphicsUnit.Point);
        using var brush = new SolidBrush(Color.Black);

        graphics.DrawRectangle(borderPen, 2f, 2f, WidthMillimetres - 4f, HeightMillimetres - 4f);
        graphics.DrawString("EBIR", brandFont, brush, 6f, 4f);
        graphics.DrawString(label.ProductPostingGroup, headingFont, brush, 95f, 7f);
        graphics.DrawLine(dividerPen, 4f, 18f, 146f, 18f);

        graphics.DrawString(label.PalletCode, mainCodeFont, brush, new RectangleF(6f, 21f, 138f, 13f));
        DrawField(graphics, brush, headingFont, valueFont, "ARTICULO", label.ProductCode, 6f, 38f, 43f);
        DrawField(graphics, brush, headingFont, valueFont, "ORDEN", label.ProductionOrderNumber, 52f, 38f, 43f);
        DrawField(graphics, brush, headingFont, valueFont, "LOTE", label.Lot, 98f, 38f, 46f);

        using var ellipsisWord = new StringFormat { Trimming = StringTrimming.EllipsisWord };
        using var ellipsisCharacter = new StringFormat { Trimming = StringTrimming.EllipsisCharacter };
        graphics.DrawString(
            label.ProductDescription,
            valueFont,
            brush,
            new RectangleF(6f, 54f, 91f, 18f),
            ellipsisWord);
        graphics.DrawString("CANTIDAD", headingFont, brush, 101f, 53f);
        graphics.DrawString(
            label.Quantity.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture),
            quantityFont,
            brush,
            new RectangleF(100f, 61f, 43f, 18f));

        graphics.DrawLine(dividerPen, 4f, 80f, 146f, 80f);
        graphics.DrawString("LINEA", headingFont, brush, 6f, 83f);
        graphics.DrawString(label.AssemblyLineName, valueFont, brush, new RectangleF(27f, 82f, 117f, 11f), ellipsisCharacter);

        graphics.PageUnit = previousUnit;
        graphics.SmoothingMode = previousSmoothing;
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
        graphics.DrawString(value, valueFont, brush, new RectangleF(x, y + 7f, width, 9f), format);
    }
}
