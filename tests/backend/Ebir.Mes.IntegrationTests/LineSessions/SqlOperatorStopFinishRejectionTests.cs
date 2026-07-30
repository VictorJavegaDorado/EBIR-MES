using Ebir.Mes.Infrastructure.LineSessions;
using Xunit;

namespace Ebir.Mes.IntegrationTests.LineSessions;

public sealed class SqlOperatorStopFinishRejectionTests
{
    public static TheoryData<int, string> Cases => new()
    {
        {52300,"CORRELATION_ID_REQUIRED"},{52301,"EMPLOYEE_NOT_ACTIVE_OPERATOR"},
        {52302,"LINE_SESSION_NOT_FOUND"},{52303,"ORDER_STATE_NOT_ALLOWED_FOR_RETURN"},
        {52304,"LINE_SESSION_NOT_ACTIVE"},{52305,"LINE_SESSION_CHANGED"},
        {52306,"LINE_SESSION_STATE_NOT_ALLOWED_FOR_RETURN"},{52307,"LINE_SESSION_MISMATCH"},
        {52308,"LINE_STATE_NOT_ALLOWED_FOR_RETURN"},{52309,"EMPLOYEE_TIME_ENTRY_NOT_OPEN"},
        {52310,"OPERATOR_STOP_NOT_OPEN"},{52311,"SUBSTITUTION_STOP_MISMATCH"},
        {52312,"SUBSTITUTE_TIME_ENTRY_NOT_OPEN"},{52313,"EMPLOYEE_ROLE_CHANGED"},
        {52314,"OPERATOR_STOP_CHANGED"},{52315,"SUBSTITUTION_CHANGED"},
        {52316,"SUBSTITUTE_TIME_ENTRY_CLOSE_FAILED"},{52317,"NO_EFFECTIVE_RESOURCES_AFTER_RETURN"}
    };

    [Theory, MemberData(nameof(Cases))]
    public void TryTranslate_MapsKnownErrors(int number, string code)
    {
        Assert.True(SqlOperatorStopFinisher.TryTranslate(number, out var rejection));
        Assert.Equal(code, rejection.Code);
        Assert.DoesNotContain(number.ToString(), rejection.Message);
    }

    [Fact]
    public void TryTranslate_RejectsUnknown() =>
        Assert.False(SqlOperatorStopFinisher.TryTranslate(52318, out _));
}
