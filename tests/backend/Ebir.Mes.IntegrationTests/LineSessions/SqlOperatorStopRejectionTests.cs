using Ebir.Mes.Infrastructure.LineSessions;
using Xunit;

namespace Ebir.Mes.IntegrationTests.LineSessions;

public sealed class SqlOperatorStopRejectionTests
{
    [Theory]
    [InlineData(52200, "CORRELATION_ID_REQUIRED")]
    [InlineData(52201, "STOP_REASON_INVALID")]
    [InlineData(52202, "EMPLOYEE_NOT_ACTIVE_OPERATOR")]
    [InlineData(52203, "LINE_SESSION_NOT_FOUND")]
    [InlineData(52204, "ORDER_STATE_NOT_ALLOWED_FOR_STOP")]
    [InlineData(52205, "LINE_SESSION_NOT_ACTIVE")]
    [InlineData(52206, "LINE_SESSION_CHANGED")]
    [InlineData(52207, "LINE_SESSION_STATE_NOT_ALLOWED_FOR_STOP")]
    [InlineData(52208, "LINE_SESSION_MISMATCH")]
    [InlineData(52209, "LINE_STATE_NOT_ALLOWED_FOR_STOP")]
    [InlineData(52210, "EMPLOYEE_TIME_ENTRY_NOT_OPEN")]
    [InlineData(52211, "OPERATOR_STOP_ALREADY_OPEN")]
    [InlineData(52212, "EMPLOYEE_IS_ACTIVE_SUBSTITUTE")]
    [InlineData(52213, "EMPLOYEE_ROLE_CHANGED")]
    public void TryTranslate_MapsKnownErrors(int number, string code)
    {
        Assert.True(SqlOperatorStopStarter.TryTranslate(number, out var rejection));
        Assert.Equal(code, rejection.Code);
        Assert.DoesNotContain(number.ToString(), rejection.Message);
    }

    [Fact]
    public void TryTranslate_RejectsUnknownErrors() =>
        Assert.False(SqlOperatorStopStarter.TryTranslate(52214, out _));
}
