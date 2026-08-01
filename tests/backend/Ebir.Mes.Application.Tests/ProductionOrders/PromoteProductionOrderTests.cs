using Ebir.Mes.Application.ProductionOrders;
using Xunit;

namespace Ebir.Mes.Application.Tests.ProductionOrders;

public sealed class PromoteProductionOrderTests
{
    [Fact]
    public async Task ExecuteAsync_normalizes_and_promotes_snapshot_contract()
    {
        var store = new StubStore();
        var correlation = Guid.NewGuid();
        var result = await new PromoteProductionOrder(store).ExecuteAsync(
            new(2, " 20 ", correlation),
            CancellationToken.None);
        Assert.Equal(42, result.ProductionOrderId);
        Assert.Equal("20", store.Command!.OperationNumber);
        Assert.Equal(correlation, store.Command.CorrelationId);
    }

    [Theory]
    [InlineData(0, "20", "NAV_INBOUND_ORDER_INVALID")]
    [InlineData(2, "", "NAV_PROMOTION_OPERATION_INVALID")]
    public async Task ExecuteAsync_rejects_invalid_contract(
        long inboundOrderId, string operation, string expectedCode)
    {
        var exception = await Assert.ThrowsAsync<ProductionOrderPromotionRejectedException>(
            () => new PromoteProductionOrder(new StubStore()).ExecuteAsync(
                new(inboundOrderId, operation, Guid.NewGuid()),
                CancellationToken.None));
        Assert.Equal(expectedCode, exception.Code);
    }

    [Fact]
    public async Task ExecuteAsync_rejects_empty_correlation()
    {
        var exception = await Assert.ThrowsAsync<ProductionOrderPromotionRejectedException>(
            () => new PromoteProductionOrder(new StubStore()).ExecuteAsync(
                new(2, "20", Guid.Empty), CancellationToken.None));
        Assert.Equal("NAV_PROMOTION_ID_REQUIRED", exception.Code);
    }

    private sealed class StubStore : IProductionOrderPromotionStore
    {
        public ProductionOrderPromotionCommand? Command { get; private set; }
        public Task<ProductionOrderPromotionResult> PromoteAsync(
            ProductionOrderPromotionCommand command,
            CancellationToken cancellationToken)
        {
            Command = command;
            return Task.FromResult(new ProductionOrderPromotionResult(
                42, ProductionOrderPromotionOutcome.Created));
        }
    }
}
