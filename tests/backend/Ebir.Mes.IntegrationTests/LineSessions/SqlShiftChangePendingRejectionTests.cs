using Ebir.Mes.Infrastructure.LineSessions;
using Xunit;

namespace Ebir.Mes.IntegrationTests.LineSessions;

public sealed class SqlShiftChangePendingRejectionTests
{
    [Theory]
    [InlineData(52000, "LINE_SESSION_NOT_ACTIVE")]
    [InlineData(52001, "SHIFT_NOT_SUPPORTED")]
    [InlineData(52002, "SHIFT_CHANGE_NOT_REACHED")]
    [InlineData(52003, "CORRELATION_ID_REQUIRED")]
    public void TryTranslate_MapsEveryExpectedSqlRejection(
        int number,
        string expectedCode)
    {
        var translated = SqlShiftChangePendingMarker.TryTranslate(
            number,
            out var rejection);

        Assert.True(translated);
        Assert.Equal(expectedCode, rejection.Code);
        Assert.DoesNotContain(number.ToString(), rejection.Message);
    }

    [Fact]
    public void TryTranslate_DoesNotClassifyUnexpectedSqlErrors() =>
        Assert.False(SqlShiftChangePendingMarker.TryTranslate(52004, out _));
}
