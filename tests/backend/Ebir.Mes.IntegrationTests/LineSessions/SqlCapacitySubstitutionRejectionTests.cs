using Ebir.Mes.Infrastructure.LineSessions;
using Xunit;

namespace Ebir.Mes.IntegrationTests.LineSessions;

public sealed class SqlCapacitySubstitutionRejectionTests
{
    public static TheoryData<int, string> Cases => new()
    {
        {52400,"CORRELATION_ID_REQUIRED"},{52401,"SUBSTITUTION_REASON_REQUIRED"},
        {52402,"SUBSTITUTION_EMPLOYEES_MUST_DIFFER"},{52403,"REPLACED_EMPLOYEE_NOT_ACTIVE_OPERATOR"},
        {52404,"SUBSTITUTE_NOT_ACTIVE_SUPERVISOR"},{52405,"LINE_SESSION_NOT_FOUND"},
        {52406,"ORDER_STATE_NOT_ALLOWED_FOR_SUBSTITUTION"},{52407,"LINE_SESSION_NOT_ACTIVE"},
        {52408,"LINE_SESSION_CHANGED"},{52409,"LINE_SESSION_STATE_NOT_ALLOWED_FOR_SUBSTITUTION"},
        {52410,"LINE_SESSION_MISMATCH"},{52411,"LINE_STATE_NOT_ALLOWED_FOR_SUBSTITUTION"},
        {52412,"REPLACED_OPERATOR_TIME_ENTRY_NOT_OPEN"},{52413,"SUBSTITUTE_TIME_ENTRY_ALREADY_OPEN"},
        {52414,"REPLACED_OPERATOR_STOP_NOT_OPEN"},{52415,"EMPLOYEE_SUBSTITUTION_ALREADY_ACTIVE"},
        {52416,"REPLACED_OPERATOR_ROLE_CHANGED"},{52417,"SUBSTITUTE_SUPERVISOR_ROLE_CHANGED"},
        {52418,"SUBSTITUTION_RESOURCE_COUNT_INVALID"}
    };

    [Theory, MemberData(nameof(Cases))]
    public void TryTranslate_MapsKnownErrors(int number, string code)
    {
        Assert.True(SqlCapacitySubstitutionStarter.TryTranslate(
            number, out var rejection));
        Assert.Equal(code, rejection.Code);
        Assert.DoesNotContain(number.ToString(), rejection.Message);
    }

    [Fact]
    public void TryTranslate_RejectsUnknown() =>
        Assert.False(SqlCapacitySubstitutionStarter.TryTranslate(52419, out _));
}
