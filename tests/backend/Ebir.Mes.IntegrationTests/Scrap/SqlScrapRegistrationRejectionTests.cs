using Ebir.Mes.Infrastructure.Scrap;
using Xunit;

namespace Ebir.Mes.IntegrationTests.Scrap;

public sealed class SqlScrapRegistrationRejectionTests
{
    public static TheoryData<int, string> Cases => new()
    {
        {55000,"LINE_SESSION_ID_REQUIRED"},{55001,"ORDER_COMPONENT_ID_REQUIRED"},
        {55002,"SCRAP_REASON_ID_REQUIRED"},{55003,"SCRAP_QUANTITY_INVALID"},
        {55004,"REGISTERED_BY_EMPLOYEE_ID_REQUIRED"},
        {55005,"CORRELATION_ID_REQUIRED"},
        {55006,"SCRAP_IDEMPOTENCY_LOCK_UNAVAILABLE"},
        {55007,"CORRELATION_ID_ALREADY_USED"},
        {55008,"PREVIOUS_SCRAP_REGISTRATION_INCOMPLETE"},
        {55009,"LINE_SESSION_NOT_ACTIVE"},
        {55010,"LINE_SESSION_STATE_NOT_ALLOWED_FOR_SCRAP"},
        {55011,"ORDER_STATE_NOT_ALLOWED_FOR_SCRAP"},
        {55012,"SCRAP_REGISTRAR_ROLE_NOT_ALLOWED"},
        {55013,"ORDER_COMPONENT_NOT_FOUND"},{55014,"SCRAP_REASON_NOT_ACTIVE"},
        {55015,"SCRAP_DESCRIPTION_REQUIRED"},
        {55016,"CORRELATION_ID_PARAMETER_MISMATCH"}
    };

    [Theory, MemberData(nameof(Cases))]
    public void TryTranslate_MapsKnownErrors(int number, string code)
    {
        Assert.True(SqlScrapRegistrar.TryTranslate(number, out var rejection));
        Assert.Equal(code, rejection.Code);
        Assert.DoesNotContain(number.ToString(), rejection.Message);
    }

    [Fact]
    public void TryTranslate_RejectsUnknown() =>
        Assert.False(SqlScrapRegistrar.TryTranslate(55017, out _));
}
