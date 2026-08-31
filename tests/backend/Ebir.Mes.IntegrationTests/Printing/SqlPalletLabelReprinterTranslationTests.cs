using Ebir.Mes.Infrastructure.Printing;
using Xunit;

namespace Ebir.Mes.IntegrationTests.Printing;

public sealed class SqlPalletLabelReprinterTranslationTests
{
    [Theory]
    [InlineData(56500, "PALLET_ID_REQUIRED")]
    [InlineData(56506, "CORRELATION_ID_PARAMETER_MISMATCH")]
    [InlineData(56508, "REPRINT_SUPERVISOR_NOT_ACTIVE")]
    [InlineData(56510, "PALLET_LABEL_NOT_PRINTED")]
    [InlineData(56512, "PALLET_LABEL_PRINT_ALREADY_OPEN")]
    [InlineData(56513, "PRIMARY_PRINTER_NOT_AVAILABLE")]
    public void TryTranslate_ReturnsSafeFunctionalCode(int number, string code)
    {
        Assert.True(SqlPalletLabelReprinter.TryTranslate(number, out var rejection));
        Assert.Equal(code, rejection.Code);
    }

    [Fact]
    public void TryTranslate_LeavesUnknownSqlErrorUnavailable()
    {
        Assert.False(SqlPalletLabelReprinter.TryTranslate(56599, out _));
    }
}
