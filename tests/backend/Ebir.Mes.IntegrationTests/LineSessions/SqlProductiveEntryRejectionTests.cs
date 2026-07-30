using Ebir.Mes.Infrastructure.LineSessions;
using Xunit;

namespace Ebir.Mes.IntegrationTests.LineSessions;

public sealed class SqlProductiveEntryRejectionTests
{
    [Theory]
    [InlineData(51800, "EMPLOYEE_NOT_ACTIVE_OPERATOR")]
    [InlineData(51801, "LINE_SESSION_NOT_FOUND")]
    [InlineData(51802, "ORDER_NOT_AVAILABLE_FOR_ENTRY")]
    [InlineData(51803, "LINE_SESSION_NOT_ACTIVE")]
    [InlineData(51804, "LINE_SESSION_CHANGED")]
    [InlineData(51805, "LINE_SESSION_STATE_NOT_ALLOWED")]
    [InlineData(51806, "LINE_SESSION_MISMATCH")]
    [InlineData(51807, "LINE_STATE_NOT_ALLOWED_FOR_ENTRY")]
    [InlineData(51808, "EMPLOYEE_TIME_ENTRY_ALREADY_OPEN")]
    [InlineData(51809, "NO_PENDING_QUANTITY_FOR_PRODUCTION")]
    [InlineData(51810, "EMPLOYEE_ROLE_CHANGED")]
    public void TryTranslate_MapsEveryExpectedSqlRejection(
        int number,
        string expectedCode)
    {
        var translated = SqlProductiveEntryRegistrar.TryTranslate(
            number,
            out var rejection);

        Assert.True(translated);
        Assert.Equal(expectedCode, rejection.Code);
        Assert.DoesNotContain(number.ToString(), rejection.Message);
    }

    [Fact]
    public void TryTranslate_DoesNotClassifyUnexpectedSqlErrors() =>
        Assert.False(SqlProductiveEntryRegistrar.TryTranslate(51811, out _));
}
