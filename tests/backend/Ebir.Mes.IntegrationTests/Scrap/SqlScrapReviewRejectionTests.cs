using Ebir.Mes.Infrastructure.Scrap;
using Xunit;

namespace Ebir.Mes.IntegrationTests.Scrap;

public sealed class SqlScrapReviewRejectionTests
{
    public static TheoryData<int, string> Cases => new()
    {
        {55100,"SCRAP_ID_REQUIRED"},{55101,"ORDER_COMPONENT_ID_REQUIRED"},
        {55102,"SCRAP_REASON_ID_REQUIRED"},{55103,"SCRAP_REVIEW_TYPE_REQUIRED"},
        {55104,"SCRAP_REVIEW_QUANTITY_INVALID"},
        {55105,"ADJUSTED_BY_SUPERVISOR_ID_REQUIRED"},
        {55106,"SCRAP_ADJUSTMENT_REASON_REQUIRED"},
        {55107,"CORRELATION_ID_REQUIRED"},
        {55108,"SCRAP_REVIEW_IDEMPOTENCY_LOCK_UNAVAILABLE"},
        {55109,"CORRELATION_ID_ALREADY_USED"},
        {55110,"CORRELATION_ID_PARAMETER_MISMATCH"},
        {55111,"SCRAP_NOT_FOUND"},{55112,"SCRAP_ORDER_NOT_FOUND"},
        {55113,"SUPERVISOR_NOT_ACTIVE"},{55114,"ORDER_COMPONENT_NOT_FOUND"},
        {55115,"SCRAP_REASON_NOT_ACTIVE"},{55116,"SCRAP_DESCRIPTION_REQUIRED"},
        {55117,"SCRAP_REVIEW_HAS_NO_CHANGES"},
        {55118,"SCRAP_NAV_OPERATION_NOT_FOUND"},
        {55119,"SCRAP_NAV_RESULT_PENDING_OR_UNKNOWN"},
        {55120,"SCRAP_ACCUMULATED_QUANTITY_NEGATIVE"},
        {55121,"PREVIOUS_SCRAP_REVIEW_INCOMPLETE"},
        {55122,"SCRAP_TRANSACTION_LOCK_UNAVAILABLE"}
    };

    [Theory, MemberData(nameof(Cases))]
    public void TryTranslate_MapsKnownErrors(int number, string code)
    {
        Assert.True(SqlScrapReviewer.TryTranslate(number, out var rejection));
        Assert.Equal(code, rejection.Code);
        Assert.DoesNotContain(number.ToString(), rejection.Message);
    }

    [Fact]
    public void TryTranslate_RejectsUnknown() =>
        Assert.False(SqlScrapReviewer.TryTranslate(55123, out _));
}
