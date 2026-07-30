using Ebir.Mes.Infrastructure.LineSessions;
using Xunit;

namespace Ebir.Mes.IntegrationTests.LineSessions;

public sealed class SqlProductiveExitRejectionTests
{
    [Theory]
    [InlineData(51900, "LINE_SESSION_NOT_FOUND")]
    [InlineData(51901, "ORDER_NOT_FOUND")]
    [InlineData(51902, "LINE_SESSION_NOT_ACTIVE")]
    [InlineData(51903, "LINE_SESSION_CHANGED")]
    [InlineData(51904, "LINE_SESSION_STATE_NOT_ALLOWED_FOR_EXIT")]
    [InlineData(51905, "LINE_SESSION_MISMATCH")]
    [InlineData(51906, "LINE_STATE_NOT_ALLOWED_FOR_EXIT")]
    [InlineData(51907, "EMPLOYEE_TIME_ENTRY_NOT_OPEN")]
    [InlineData(51908, "EMPLOYEE_STOP_STILL_OPEN")]
    [InlineData(51909, "EMPLOYEE_SUBSTITUTION_STILL_ACTIVE")]
    public void TryTranslate_MapsEveryExpectedSqlRejection(
        int number,
        string expectedCode)
    {
        var translated = SqlProductiveExitRegistrar.TryTranslate(
            number,
            out var rejection);

        Assert.True(translated);
        Assert.Equal(expectedCode, rejection.Code);
        Assert.DoesNotContain(number.ToString(), rejection.Message);
    }

    [Fact]
    public void TryTranslate_DoesNotClassifyUnexpectedSqlErrors() =>
        Assert.False(SqlProductiveExitRegistrar.TryTranslate(51910, out _));
}
