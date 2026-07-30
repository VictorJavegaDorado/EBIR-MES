using Ebir.Mes.Infrastructure.LineSessions;
using Xunit;

namespace Ebir.Mes.IntegrationTests.LineSessions;

public sealed class SqlCurrentShiftTimeEntryCorrectionRejectionTests
{
    public static TheoryData<int, string> Cases => new()
    {
        {52600,"CORRELATION_ID_REQUIRED"},{52601,"CORRECTED_ENTRY_UTC_REQUIRED"},
        {52602,"CORRECTED_EXIT_BEFORE_ENTRY"},
        {52603,"TIME_ENTRY_CORRECTION_REASON_REQUIRED"},
        {52604,"SUPERVISOR_NOT_ACTIVE"},{52605,"TIME_ENTRY_NOT_FOUND"},
        {52606,"TIME_ENTRY_LINE_SESSION_NOT_FOUND"},
        {52607,"FUTURE_TIME_ENTRY_CORRECTION_NOT_ALLOWED"},
        {52608,"ORDER_NOT_FOUND"},{52609,"LINE_SESSION_NOT_ACTIVE"},
        {52610,"LINE_SESSION_CHANGED"},
        {52611,"LINE_SESSION_STATE_NOT_ALLOWED_FOR_TIME_ENTRY_CORRECTION"},
        {52612,"CORRECTED_ENTRY_BEFORE_LINE_SESSION_LOAD"},
        {52613,"LINE_SESSION_MISMATCH"},{52614,"TIME_ENTRY_CHANGED"},
        {52615,"EMPLOYEE_HAS_ANOTHER_OPEN_TIME_ENTRY"},
        {52616,"TIME_ENTRY_INTERVAL_OVERLAP"},
        {52617,"OPERATOR_STOP_OUTSIDE_CORRECTED_TIME_ENTRY"},
        {52618,"CAPACITY_SUBSTITUTION_OUTSIDE_CORRECTED_TIME_ENTRY"},
        {52619,"ACTIVE_CAPACITY_SUBSTITUTION_PREVENTS_TIME_ENTRY_CORRECTION"},
        {52620,"CORRECTING_SUPERVISOR_ROLE_CHANGED"},
        {52621,"LINE_SESSION_HAS_NO_TIME_ENTRIES"}
    };

    [Theory, MemberData(nameof(Cases))]
    public void TryTranslate_MapsKnownErrors(int number, string code)
    {
        Assert.True(SqlCurrentShiftTimeEntryCorrector.TryTranslate(
            number, out var rejection));
        Assert.Equal(code, rejection.Code);
        Assert.DoesNotContain(number.ToString(), rejection.Message);
    }

    [Fact]
    public void TryTranslate_RejectsUnknown() =>
        Assert.False(SqlCurrentShiftTimeEntryCorrector.TryTranslate(52622, out _));
}
