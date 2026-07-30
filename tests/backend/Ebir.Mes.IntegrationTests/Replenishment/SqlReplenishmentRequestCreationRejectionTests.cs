using Ebir.Mes.Infrastructure.Replenishment;
using Xunit;

namespace Ebir.Mes.IntegrationTests.Replenishment;

public sealed class SqlReplenishmentRequestCreationRejectionTests
{
    public static TheoryData<int, string> Cases => new()
    {
        {55200,"LINE_SESSION_ID_REQUIRED"},{55201,"ORDER_COMPONENT_ID_REQUIRED"},
        {55202,"REQUESTED_QUANTITY_INVALID"},
        {55203,"REQUESTED_BY_EMPLOYEE_ID_REQUIRED"},
        {55204,"CORRELATION_ID_REQUIRED"},
        {55205,"REPLENISHMENT_IDEMPOTENCY_LOCK_UNAVAILABLE"},
        {55206,"CORRELATION_ID_ALREADY_USED"},
        {55207,"CORRELATION_ID_PARAMETER_MISMATCH"},
        {55208,"LINE_SESSION_NOT_ACTIVE"},
        {55209,"LINE_SESSION_STATE_NOT_ALLOWED_FOR_REPLENISHMENT"},
        {55210,"ORDER_STATE_NOT_ALLOWED_FOR_REPLENISHMENT"},
        {55211,"REPLENISHMENT_REQUESTER_ROLE_NOT_ALLOWED"},
        {55212,"ORDER_COMPONENT_NOT_FOUND"},{55213,"LINKED_SCRAP_NOT_FOUND"},
        {55214,"LINKED_SCRAP_CONTEXT_MISMATCH"},{55215,"LINKED_SCRAP_CANCELLED"},
        {55216,"LINKED_SCRAP_COMPONENT_MISMATCH"},
        {55217,"LINKED_SCRAP_TRANSACTION_LOCK_UNAVAILABLE"}
    };

    [Theory, MemberData(nameof(Cases))]
    public void TryTranslate_MapsKnownErrors(int number, string code)
    {
        Assert.True(SqlReplenishmentRequestCreator.TryTranslate(
            number, out var rejection));
        Assert.Equal(code, rejection.Code);
        Assert.DoesNotContain(number.ToString(), rejection.Message);
    }

    [Fact]
    public void TryTranslate_RejectsUnknown() =>
        Assert.False(SqlReplenishmentRequestCreator.TryTranslate(55218, out _));
}
