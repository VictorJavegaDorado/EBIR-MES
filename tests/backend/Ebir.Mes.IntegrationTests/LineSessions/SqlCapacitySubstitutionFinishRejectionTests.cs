using Ebir.Mes.Infrastructure.LineSessions;
using Xunit;

namespace Ebir.Mes.IntegrationTests.LineSessions;

public sealed class SqlCapacitySubstitutionFinishRejectionTests
{
    public static TheoryData<int, string> Cases => new()
    {
        {52500,"CORRELATION_ID_REQUIRED"},{52501,"SUBSTITUTION_FINISH_REASON_REQUIRED"},
        {52502,"SUPERVISOR_NOT_ACTIVE"},{52503,"CAPACITY_SUBSTITUTION_NOT_FOUND"},
        {52504,"SUBSTITUTION_LINE_SESSION_NOT_FOUND"},
        {52505,"ORDER_STATE_NOT_ALLOWED_FOR_SUBSTITUTION_FINISH"},
        {52506,"LINE_SESSION_NOT_ACTIVE"},{52507,"LINE_SESSION_CHANGED"},
        {52508,"LINE_SESSION_STATE_NOT_ALLOWED_FOR_SUBSTITUTION_FINISH"},
        {52509,"LINE_SESSION_MISMATCH"},
        {52510,"LINE_STATE_NOT_ALLOWED_FOR_SUBSTITUTION_FINISH"},
        {52511,"REPLACED_OPERATOR_TIME_ENTRY_NOT_OPEN"},
        {52512,"SUBSTITUTE_TIME_ENTRY_NOT_OPEN"},
        {52513,"REPLACED_OPERATOR_STOP_NOT_OPEN"},
        {52514,"CAPACITY_SUBSTITUTION_NOT_ACTIVE"},
        {52515,"AUTHORIZING_SUPERVISOR_ROLE_CHANGED"},
        {52516,"SUBSTITUTION_HAS_NO_EFFECTIVE_RESOURCE"},
        {52517,"CAPACITY_SUBSTITUTION_FINISH_FAILED"},
        {52518,"SUBSTITUTE_TIME_ENTRY_CLOSE_FAILED"},
        {52519,"SUBSTITUTION_RESOURCE_COUNT_INVALID"}
    };

    [Theory, MemberData(nameof(Cases))]
    public void TryTranslate_MapsKnownErrors(int number, string code)
    {
        Assert.True(SqlCapacitySubstitutionFinisher.TryTranslate(
            number, out var rejection));
        Assert.Equal(code, rejection.Code);
        Assert.DoesNotContain(number.ToString(), rejection.Message);
    }

    [Fact]
    public void TryTranslate_RejectsUnknown() =>
        Assert.False(SqlCapacitySubstitutionFinisher.TryTranslate(52520, out _));
}
