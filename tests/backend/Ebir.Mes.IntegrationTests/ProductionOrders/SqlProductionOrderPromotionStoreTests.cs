using Ebir.Mes.Infrastructure.ProductionOrders;
using Xunit;

namespace Ebir.Mes.IntegrationTests.ProductionOrders;

public sealed class SqlProductionOrderPromotionStoreTests
{
    [Theory]
    [InlineData(55600, false)]
    [InlineData(55601, false)]
    [InlineData(55602, false)]
    [InlineData(55603, false)]
    [InlineData(55604, false)]
    [InlineData(55605, false)]
    [InlineData(55606, false)]
    [InlineData(55607, false)]
    [InlineData(55608, false)]
    [InlineData(55609, false)]
    [InlineData(55610, false)]
    [InlineData(55611, true)]
    [InlineData(55612, false)]
    [InlineData(55613, false)]
    [InlineData(55614, false)]
    [InlineData(55615, false)]
    [InlineData(55616, false)]
    public void TryTranslate_maps_known_errors(int number, bool unavailable)
    {
        Assert.True(SqlProductionOrderPromotionStore.TryTranslate(number, out var rejection));
        Assert.Equal(unavailable, rejection.Unavailable);
        Assert.False(string.IsNullOrWhiteSpace(rejection.Code));
    }

    [Fact]
    public void TryTranslate_does_not_map_unknown_error() =>
        Assert.False(SqlProductionOrderPromotionStore.TryTranslate(59999, out _));
}
