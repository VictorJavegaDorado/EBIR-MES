using Ebir.Mes.Application.Replenishment;
using Xunit;

namespace Ebir.Mes.Application.Tests.Replenishment;

public sealed class CreateReplenishmentRequestTests
{
    [Fact]
    public async Task ExecuteAsync_CreatesRequest()
    {
        var creator = new StubCreator();
        var command = new CreateReplenishmentRequestCommand(
            12, 25, 4, 7, 31, Guid.NewGuid());
        var result = await new CreateReplenishmentRequest(creator).ExecuteAsync(
            command,
            CancellationToken.None);
        Assert.Equal(CreateReplenishmentRequestOutcome.Created, result.Outcome);
        Assert.Equal(41, result.RequestId);
        Assert.Equal(command, creator.Command);
    }

    [Theory]
    [InlineData(0, 25, 4, 7, null, "LINE_SESSION_ID_INVALID")]
    [InlineData(12, 0, 4, 7, null, "ORDER_COMPONENT_ID_INVALID")]
    [InlineData(12, 25, 0, 7, null, "REQUESTED_QUANTITY_INVALID")]
    [InlineData(12, 25, 4, 0, null, "REQUESTED_BY_EMPLOYEE_ID_INVALID")]
    public async Task ExecuteAsync_ValidatesPositiveValues(
        long session,
        long component,
        int quantity,
        long employee,
        long? scrap,
        string code)
    {
        var result = await new CreateReplenishmentRequest(new StubCreator())
            .ExecuteAsync(
                new(session, component, quantity, employee, scrap, Guid.NewGuid()),
                CancellationToken.None);
        Assert.Equal(code, result.ErrorCode);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsInvalidLinkedScrap()
    {
        var result = await new CreateReplenishmentRequest(new StubCreator())
            .ExecuteAsync(
                new(12, 25, 4, 7, 0, Guid.NewGuid()),
                CancellationToken.None);
        Assert.Equal("SCRAP_ID_INVALID", result.ErrorCode);
    }

    [Fact]
    public async Task ExecuteAsync_AllowsRequestWithoutScrap()
    {
        var creator = new StubCreator();
        var result = await new CreateReplenishmentRequest(creator).ExecuteAsync(
            new(12, 25, 4, 7, null, Guid.NewGuid()),
            CancellationToken.None);
        Assert.Equal(CreateReplenishmentRequestOutcome.Created, result.Outcome);
        Assert.Null(creator.Command!.ScrapId);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsEmptyCorrelation()
    {
        var result = await new CreateReplenishmentRequest(new StubCreator())
            .ExecuteAsync(
                new(12, 25, 4, 7, null, Guid.Empty),
                CancellationToken.None);
        Assert.Equal("CORRELATION_ID_INVALID", result.ErrorCode);
    }

    private sealed class StubCreator : IReplenishmentRequestCreator
    {
        public CreateReplenishmentRequestCommand? Command { get; private set; }

        public Task<long> CreateAsync(
            CreateReplenishmentRequestCommand command,
            CancellationToken cancellationToken)
        {
            Command = command;
            return Task.FromResult(41L);
        }
    }
}
