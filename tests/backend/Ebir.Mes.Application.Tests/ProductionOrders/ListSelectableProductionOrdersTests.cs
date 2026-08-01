using Ebir.Mes.Application.ProductionOrders;
using Xunit;

namespace Ebir.Mes.Application.Tests.ProductionOrders;

public sealed class ListSelectableProductionOrdersTests
{
    [Fact]
    public async Task ExecuteAsync_returns_reader_results()
    {
        var expected = new ProductionOrderSelectionRecord(
            28, "FL20-02277", "27979CI", "ESPEJO", "FL2002277",
            10, 0, 0, 0, 36m, "IMPORTADA", DateTime.UtcNow);
        var result = await new ListSelectableProductionOrders(
                new StubReader([expected]))
            .ExecuteAsync(CancellationToken.None);

        Assert.Same(expected, Assert.Single(result));
    }

    private sealed class StubReader(
        IReadOnlyList<ProductionOrderSelectionRecord> records)
        : IProductionOrderSelectionReader
    {
        public Task<IReadOnlyList<ProductionOrderSelectionRecord>> ReadAsync(
            CancellationToken cancellationToken) => Task.FromResult(records);
    }
}
