using System.Drawing.Printing;
using Ebir.Mes.Integrations.Printing;
using Xunit;

namespace Ebir.Mes.Integrations.Windows.Tests.Printing;

public sealed class WindowsSpoolerClientTests
{
    [Fact]
    public void ConfigurePalletPage_uses_supported_media_width_in_landscape()
    {
        var settings = new PageSettings();

        WindowsSpoolerClient.ConfigurePalletPage(settings);

        Assert.True(settings.Landscape);
        Assert.Equal("EBIR 100x150 mm", settings.PaperSize.PaperName);
        Assert.Equal(394, settings.PaperSize.Width);
        Assert.Equal(591, settings.PaperSize.Height);
        Assert.Equal(0, settings.Margins.Left);
        Assert.Equal(0, settings.Margins.Top);
        Assert.Equal(0, settings.Margins.Right);
        Assert.Equal(0, settings.Margins.Bottom);
    }
}
