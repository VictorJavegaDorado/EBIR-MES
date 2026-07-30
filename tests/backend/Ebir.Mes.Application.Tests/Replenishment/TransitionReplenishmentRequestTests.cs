using Ebir.Mes.Application.Replenishment;
using Xunit;

namespace Ebir.Mes.Application.Tests.Replenishment;

public sealed class TransitionReplenishmentRequestTests
{
    [Theory]
    [InlineData(" aceptada ", "ACEPTADA")]
    [InlineData("en_camino", "EN_CAMINO")]
    [InlineData("Entregada", "ENTREGADA")]
    [InlineData("rechazada", "RECHAZADA")]
    [InlineData("cancelada", "CANCELADA")]
    public async Task ExecuteAsync_NormalizesAllowedState(
        string state,
        string expected)
    {
        var transitioner = new StubTransitioner();
        var result = await new TransitionReplenishmentRequest(transitioner)
            .ExecuteAsync(
                new(41, state, 8, " motivo ", Guid.NewGuid()),
                CancellationToken.None);
        Assert.Equal(
            TransitionReplenishmentRequestOutcome.Transitioned,
            result.Outcome);
        Assert.Equal(expected, result.State);
        Assert.Equal(expected, transitioner.Command!.NewState);
        Assert.Equal("motivo", transitioner.Command.Comment);
    }

    [Theory]
    [InlineData(0, "ACEPTADA", 8, "REPLENISHMENT_REQUEST_ID_INVALID")]
    [InlineData(41, "OTRO", 8, "REPLENISHMENT_TARGET_STATE_INVALID")]
    [InlineData(41, "ACEPTADA", 0, "REPLENISHMENT_EMPLOYEE_ID_INVALID")]
    public async Task ExecuteAsync_ValidatesContract(
        long request,
        string state,
        long employee,
        string code)
    {
        var result = await new TransitionReplenishmentRequest(
            new StubTransitioner()).ExecuteAsync(
                new(request, state, employee, null, Guid.NewGuid()),
                CancellationToken.None);
        Assert.Equal(code, result.ErrorCode);
    }

    [Theory]
    [InlineData("RECHAZADA")]
    [InlineData("CANCELADA")]
    public async Task ExecuteAsync_RequiresCommentForNegativeTerminalState(
        string state)
    {
        var result = await new TransitionReplenishmentRequest(
            new StubTransitioner()).ExecuteAsync(
                new(41, state, 8, " ", Guid.NewGuid()),
                CancellationToken.None);
        Assert.Equal(
            "REPLENISHMENT_TRANSITION_COMMENT_REQUIRED",
            result.ErrorCode);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsOversizedComment()
    {
        var result = await new TransitionReplenishmentRequest(
            new StubTransitioner()).ExecuteAsync(
                new(
                    41,
                    "ACEPTADA",
                    8,
                    new string(
                        'x',
                        TransitionReplenishmentRequest.MaximumCommentLength + 1),
                    Guid.NewGuid()),
                CancellationToken.None);
        Assert.Equal(
            "REPLENISHMENT_TRANSITION_COMMENT_TOO_LONG",
            result.ErrorCode);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsEmptyCorrelation()
    {
        var result = await new TransitionReplenishmentRequest(
            new StubTransitioner()).ExecuteAsync(
                new(41, "ACEPTADA", 8, null, Guid.Empty),
                CancellationToken.None);
        Assert.Equal("CORRELATION_ID_INVALID", result.ErrorCode);
    }

    private sealed class StubTransitioner : IReplenishmentRequestTransitioner
    {
        public TransitionReplenishmentRequestCommand? Command { get; private set; }

        public Task TransitionAsync(
            TransitionReplenishmentRequestCommand command,
            CancellationToken cancellationToken)
        {
            Command = command;
            return Task.CompletedTask;
        }
    }
}
