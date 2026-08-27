using System.Drawing;
using Ebir.Mes.Integrations.Printing;
using Xunit;
using ZXing;
using ZXing.Common;

namespace Ebir.Mes.Integrations.Windows.Tests.Printing;

public sealed class PalletLabelRendererTests
{
    [Theory]
    [InlineData("35798-T")]
    [InlineData("40")]
    [InlineData("35798-T;")]
    [InlineData("PAL-000014")]
    public void EncodeCode128_round_trips_scanner_value(string expected)
    {
        var matrix = PalletLabelRenderer.EncodeCode128(expected, 900);
        var pixels = new byte[matrix.Width * 80 * 3];

        for (var y = 0; y < 80; y++)
        {
            for (var x = 0; x < matrix.Width; x++)
            {
                var value = matrix[x, 0] ? (byte)0 : (byte)255;
                var offset = ((y * matrix.Width) + x) * 3;
                pixels[offset] = value;
                pixels[offset + 1] = value;
                pixels[offset + 2] = value;
            }
        }

        var source = new RGBLuminanceSource(
            pixels,
            matrix.Width,
            80,
            RGBLuminanceSource.BitmapFormat.RGB24);
        var decoded = new MultiFormatReader().decode(
            new BinaryBitmap(new HybridBinarizer(source)));

        Assert.Equal(BarcodeFormat.CODE_128, decoded.BarcodeFormat);
        Assert.Equal(expected, decoded.Text);
    }

    [Fact]
    public void Draw_renders_complete_150x100_label()
    {
        using var bitmap = new Bitmap(1200, 800);
        bitmap.SetResolution(203.2f, 203.2f);
        using var graphics = Graphics.FromImage(bitmap);
        var label = new PalletLabelContent(
            "PAL-000014",
            "OP-2026-0014",
            "35798-T",
            "TAPA CAJA CARTON E331 1200X800X40MM",
            "PALET CERRADO",
            "L-260827",
            40m,
            "LINEA PILOTO");

        PalletLabelRenderer.Draw(graphics, label);

        Assert.Equal(Color.Black.ToArgb(), bitmap.GetPixel(16, 16).ToArgb());
        Assert.Contains(
            Enumerable.Range(300, 500),
            x => bitmap.GetPixel(x, 40).ToArgb() == Color.Black.ToArgb());
        Assert.Contains(
            Enumerable.Range(200, 900),
            x => bitmap.GetPixel(x, 620).ToArgb() == Color.Black.ToArgb());
    }
}
