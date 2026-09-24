using Ebir.Mes.Application.Replenishment;
using Xunit;

namespace Ebir.Mes.Application.Tests.Replenishment;

public sealed class RequestProductionMaterialTests
{
    [Fact]
    public async Task ExecuteAsync_CreatesLocalRequestAndSendsExactNavComponent()
    {
        var creator = new Creator();
        var navision = new Navision();
        var correlation = Guid.NewGuid();
        var useCase = new RequestProductionMaterial(
            new Options([new(25, "FL26-00026", "27920", "LUNA MIA", "UN", 1, 0)]),
            creator, navision);

        var result = await useCase.ExecuteAsync(
            new(12, 25, 1, 7, correlation), CancellationToken.None);

        Assert.True(result.Succeeded);
        Assert.Equal(41, result.LocalRequestId);
        Assert.Equal(26932, result.NavRequestId);
        Assert.Equal("FL26-00026", navision.OrderNumber);
        Assert.Equal("27920", navision.ComponentCode);
        Assert.Equal(correlation, navision.CorrelationId);
        Assert.Equal(25, creator.Command!.OrderComponentId);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsComponentOutsideActiveOrder()
    {
        var navision = new Navision();
        var result = await new RequestProductionMaterial(new Options([]), new Creator(), navision)
            .ExecuteAsync(new(12, 99, 1, 7, Guid.NewGuid()), CancellationToken.None);

        Assert.False(result.Succeeded);
        Assert.Equal("ORDER_COMPONENT_NOT_FOUND", result.ErrorCode);
        Assert.Null(navision.OrderNumber);
    }

    private sealed class Options(IReadOnlyList<MaterialRequestOption> records)
        : IMaterialRequestOptionsReader
    {
        public Task<IReadOnlyList<MaterialRequestOption>> ReadAsync(long lineSessionId,
            CancellationToken cancellationToken) => Task.FromResult(records);
    }

    private sealed class Creator : IReplenishmentRequestCreator
    {
        public CreateReplenishmentRequestCommand? Command { get; private set; }
        public Task<long> CreateAsync(CreateReplenishmentRequestCommand command,
            CancellationToken cancellationToken)
        { Command = command; return Task.FromResult(41L); }
    }

    private sealed class Navision : INavisionMaterialRequester
    {
        public string? OrderNumber { get; private set; }
        public string? ComponentCode { get; private set; }
        public Guid CorrelationId { get; private set; }
        public Task<int> RequestAsync(string orderNumber, string componentCode, int quantity,
            Guid correlationId, CancellationToken cancellationToken)
        { OrderNumber = orderNumber; ComponentCode = componentCode; CorrelationId = correlationId;
          return Task.FromResult(26932); }
    }
}
