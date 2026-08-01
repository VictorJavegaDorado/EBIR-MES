using Ebir.Mes.Application.ProductionOrders;
using Ebir.Mes.Infrastructure.ProductionOrders;
using Xunit;

namespace Ebir.Mes.IntegrationTests.ProductionOrders;

public sealed class SqlProductionOrderSnapshotStoreTests
{
    [Fact]
    public void SerializeSnapshot_is_deterministic_and_uses_contract_names()
    {
        var snapshot = Snapshot();

        var first = SqlProductionOrderSnapshotStore.SerializeSnapshot(snapshot);
        var second = SqlProductionOrderSnapshotStore.SerializeSnapshot(snapshot);

        Assert.Equal(first, second);
        Assert.Contains("\"environmentCode\":\"EBIRTEST\"", first);
        Assert.Contains("\"lotNumber\":\"FL2600042\"", first);
        Assert.Contains("\"status\":\"Released\"", first);
        Assert.Contains("\"type\":\"WorkCenter\"", first);
    }

    [Fact]
    public void ComputeHash_is_stable_and_sensitive_to_the_payload()
    {
        var first = SqlProductionOrderSnapshotStore.ComputeHash("{\"a\":1}");
        var repeated = SqlProductionOrderSnapshotStore.ComputeHash("{\"a\":1}");
        var changed = SqlProductionOrderSnapshotStore.ComputeHash("{\"a\":2}");

        Assert.Equal(32, first.Length);
        Assert.Equal(first, repeated);
        Assert.NotEqual(first, changed);
    }

    [Theory]
    [InlineData(55500, false)]
    [InlineData(55501, true)]
    [InlineData(55502, true)]
    [InlineData(55503, false)]
    [InlineData(55504, true)]
    [InlineData(55505, false)]
    [InlineData(55506, false)]
    [InlineData(55507, false)]
    [InlineData(55700, false)]
    [InlineData(55701, false)]
    [InlineData(55702, false)]
    public void TryTranslate_maps_known_errors(int number, bool unavailable)
    {
        Assert.True(SqlProductionOrderSnapshotStore.TryTranslate(number, out var rejection));
        Assert.Equal(unavailable, rejection.Unavailable);
        Assert.False(string.IsNullOrWhiteSpace(rejection.Code));
    }

    [Fact]
    public void TryTranslate_does_not_map_an_unknown_error() =>
        Assert.False(SqlProductionOrderSnapshotStore.TryTranslate(59999, out _));

    private static ProductionOrderSnapshot Snapshot() => new(
        "EBIRTEST",
        "EBIR",
        "FL2600042",
        new("OF26-00042", ProductionOrderStatus.Released, "PRODUCTO", "ITEM-01",
            "RUTA-01", 100m, "FABRICA", null, null, null),
        new("OF26-00042", ProductionOrderStatus.Released, "ITEM-01", "", "PRODUCTO",
            "FABRICA", 100m, 0m, 100m, 0m, null, null, null, "BOM-01"),
        [new("OF26-00042", 10000, "RUTA-01", "010", "", "",
            ProductionRoutingStepType.WorkCenter, "CT-01", "OPERACION", null, null,
            0m, 1m, 0m, 0m, 0m, "", 0m, ProductionRoutingStatus.Planned,
            "FABRICA", false)],
        []);
}
