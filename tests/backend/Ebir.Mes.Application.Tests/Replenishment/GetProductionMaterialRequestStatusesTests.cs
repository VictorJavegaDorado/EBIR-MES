using Ebir.Mes.Application.Replenishment;
using Xunit;

namespace Ebir.Mes.Application.Tests.Replenishment;

public sealed class GetProductionMaterialRequestStatusesTests
{
    [Theory]
    [InlineData(0, "PENDING")]
    [InlineData(2, "PREPARING")]
    [InlineData(3, "PREPARING")]
    [InlineData(4, "SENT")]
    [InlineData(5, "SENT")]
    [InlineData(6, "ERROR")]
    [InlineData(7, "ERROR")]
    [InlineData(8, "ERROR")]
    public void ToState_MapsNavPickingLifecycle(int navCode, string expected) =>
        Assert.Equal(expected, GetProductionMaterialRequestStatuses.ToState(navCode));

    [Fact]
    public async Task ExecuteAsync_CombinesLocalContextWithNavStatus()
    {
        var correlation = Guid.NewGuid();
        var requestedAt = DateTime.UtcNow.AddMinutes(-2);
        var useCase = new GetProductionMaterialRequestStatuses(
            new Tracking([new(41, correlation, "27920", "LUNA MIA", 1, requestedAt)]),
            new Nav(new(26932, 2, "Sin Registrar", "APU21-1459", null, null)));

        var result = Assert.Single(await useCase.ExecuteAsync(12, CancellationToken.None));

        Assert.Equal(41, result.Id);
        Assert.Equal(26932, result.NavRequestId);
        Assert.Equal("PREPARING", result.State);
        Assert.Equal("APU21-1459", result.PickingNumber);
        Assert.Equal(correlation, result.CorrelationId);
    }

    private sealed class Tracking(IReadOnlyList<MaterialRequestTrackingRecord> records)
        : IMaterialRequestTrackingReader
    {
        public Task<IReadOnlyList<MaterialRequestTrackingRecord>> ReadAsync(
            long lineSessionId, CancellationToken cancellationToken) => Task.FromResult(records);
    }

    private sealed class Nav(NavMaterialRequestStatus? status)
        : INavisionMaterialRequestStatusReader
    {
        public Task<NavMaterialRequestStatus?> ReadAsync(
            Guid correlationId, CancellationToken cancellationToken) => Task.FromResult(status);
    }
}
