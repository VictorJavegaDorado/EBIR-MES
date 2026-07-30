using Ebir.Mes.Infrastructure.Replenishment;
using Xunit;

namespace Ebir.Mes.IntegrationTests.Replenishment;

public sealed class SqlReplenishmentRequestTransitionRejectionTests
{
    public static TheoryData<int, string> Cases => new()
    {
        {55300,"REPLENISHMENT_REQUEST_ID_REQUIRED"},
        {55301,"REPLENISHMENT_TARGET_STATE_INVALID"},
        {55302,"REPLENISHMENT_EMPLOYEE_ID_REQUIRED"},
        {55303,"REPLENISHMENT_TRANSITION_COMMENT_REQUIRED"},
        {55304,"CORRELATION_ID_REQUIRED"},
        {55305,"REPLENISHMENT_TRANSITION_IDEMPOTENCY_LOCK_UNAVAILABLE"},
        {55306,"CORRELATION_ID_PARAMETER_MISMATCH"},
        {55307,"REPLENISHMENT_REQUEST_NOT_FOUND"},
        {55308,"REPLENISHMENT_EMPLOYEE_NOT_ACTIVE"},
        {55309,"REPLENISHMENT_REQUEST_ALREADY_TERMINAL"},
        {55310,"REPLENISHMENT_REQUEST_ASSIGNEE_MISMATCH"},
        {55311,"REPLENISHMENT_TRANSITION_NOT_ALLOWED"}
    };

    [Theory, MemberData(nameof(Cases))]
    public void TryTranslate_MapsKnownErrors(int number, string code)
    {
        Assert.True(SqlReplenishmentRequestTransitioner.TryTranslate(
            number, out var rejection));
        Assert.Equal(code, rejection.Code);
        Assert.DoesNotContain(number.ToString(), rejection.Message);
    }

    [Fact]
    public void TryTranslate_RejectsUnknown() =>
        Assert.False(
            SqlReplenishmentRequestTransitioner.TryTranslate(55312, out _));
}
