using Ebir.Mes.Infrastructure.LineSessions;
using Xunit;

namespace Ebir.Mes.IntegrationTests.LineSessions;

public sealed class SqlLineSessionRejectionTests
{
    [Theory]
    [InlineData(51700, "SUPERVISOR_NOT_ACTIVE")]
    [InlineData(51701, "OUTSIDE_SCHEDULE_CONFIRMATION_REQUIRED")]
    [InlineData(51702, "ACTIVE_SHIFT_NOT_FOUND")]
    [InlineData(51703, "LINE_NOT_ACTIVE")]
    [InlineData(51704, "LINE_STATE_NOT_INITIALIZED")]
    [InlineData(51705, "LINE_NOT_AVAILABLE")]
    [InlineData(51706, "ORDER_NOT_FOUND")]
    [InlineData(51707, "ORDER_STATE_NOT_ALLOWED")]
    [InlineData(51708, "PALLET_FORMAT_NOT_AVAILABLE")]
    [InlineData(51709, "LINE_SESSION_ALREADY_ACTIVE")]
    [InlineData(51710, "ORDER_SESSION_ALREADY_ACTIVE")]
    public void TryTranslate_MapsEveryExpectedSqlRejection(
        int number, string expectedCode)
    {
        var translated = SqlLineSessionOpener.TryTranslate(number, out var rejection);
        Assert.True(translated);
        Assert.Equal(expectedCode, rejection.Code);
        Assert.DoesNotContain(number.ToString(), rejection.Message);
    }

    [Fact]
    public void TryTranslate_DoesNotClassifyUnexpectedSqlErrors() =>
        Assert.False(SqlLineSessionOpener.TryTranslate(51711, out _));
}
