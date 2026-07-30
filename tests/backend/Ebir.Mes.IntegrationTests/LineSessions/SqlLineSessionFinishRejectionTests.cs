using Ebir.Mes.Infrastructure.LineSessions;
using Xunit;

namespace Ebir.Mes.IntegrationTests.LineSessions;

public sealed class SqlLineSessionFinishRejectionTests
{
    [Theory]
    [InlineData(52100, "CORRELATION_ID_REQUIRED")]
    [InlineData(52101, "SUPERVISOR_NOT_ACTIVE")]
    [InlineData(52102, "LINE_SESSION_NOT_FOUND")]
    [InlineData(52103, "ORDER_NOT_FOUND")]
    [InlineData(52104, "LINE_SESSION_NOT_ACTIVE")]
    [InlineData(52105, "LINE_SESSION_CHANGED")]
    [InlineData(52106, "LINE_SESSION_STATE_NOT_ALLOWED_FOR_FINISH")]
    [InlineData(52107, "LINE_SESSION_MISMATCH")]
    [InlineData(52108, "LINE_STATE_NOT_ALLOWED_FOR_FINISH")]
    [InlineData(52109, "ACTIVE_PALLET_RESERVATION")]
    [InlineData(52110, "PALLET_OUTPUT_PENDING")]
    [InlineData(52111, "PALLET_LABEL_PENDING")]
    [InlineData(52112, "SUPERVISOR_ROLE_CHANGED")]
    [InlineData(52113, "ORDER_STATE_NOT_ALLOWED_FOR_FINISH")]
    public void TryTranslate_MapsKnownRejections(int number, string code)
    {
        Assert.True(SqlLineSessionFinisher.TryTranslate(number, out var rejection));
        Assert.Equal(code, rejection.Code);
        Assert.DoesNotContain(number.ToString(), rejection.Message);
    }

    [Fact]
    public void TryTranslate_RejectsUnknownNumbers() =>
        Assert.False(SqlLineSessionFinisher.TryTranslate(52114, out _));
}
