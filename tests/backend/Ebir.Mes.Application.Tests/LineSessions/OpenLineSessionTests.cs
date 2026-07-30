using Ebir.Mes.Application.LineSessions;
using Xunit;

namespace Ebir.Mes.Application.Tests.LineSessions;

public sealed class OpenLineSessionTests
{
    [Fact]
    public async Task ExecuteAsync_OpensAValidSession()
    {
        var opener = new StubOpener(73);
        var command = ValidCommand();
        var result = await new OpenLineSession(opener)
            .ExecuteAsync(command, CancellationToken.None);
        Assert.Equal(OpenLineSessionOutcome.Opened, result.Outcome);
        Assert.Equal(73, result.LineSessionId);
        Assert.Same(command, opener.LastCommand);
    }

    [Theory]
    [InlineData(0, 2, 3, 4, "ORDER_ID_INVALID")]
    [InlineData(1, 0, 3, 4, "LINE_ID_INVALID")]
    [InlineData(1, 2, 0, 4, "PALLET_FORMAT_ORDER_ID_INVALID")]
    [InlineData(1, 2, 3, 0, "SUPERVISOR_ID_INVALID")]
    public async Task ExecuteAsync_RejectsNonPositiveIdentifiers(
        long orderId, long lineId, long palletFormatOrderId,
        long supervisorId, string expectedCode)
    {
        var opener = new StubOpener(73);
        var command = new OpenLineSessionCommand(
            orderId, lineId, palletFormatOrderId, supervisorId, false, Guid.NewGuid());
        var result = await new OpenLineSession(opener)
            .ExecuteAsync(command, CancellationToken.None);
        Assert.Equal(OpenLineSessionOutcome.InvalidRequest, result.Outcome);
        Assert.Equal(expectedCode, result.ErrorCode);
        Assert.Null(opener.LastCommand);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsEmptyCorrelationId()
    {
        var opener = new StubOpener(73);
        var result = await new OpenLineSession(opener).ExecuteAsync(
            ValidCommand() with { CorrelationId = Guid.Empty }, CancellationToken.None);
        Assert.Equal(OpenLineSessionOutcome.InvalidRequest, result.Outcome);
        Assert.Equal("CORRELATION_ID_INVALID", result.ErrorCode);
        Assert.Null(opener.LastCommand);
    }

    [Fact]
    public async Task ExecuteAsync_ReturnsSafeFunctionalRejection()
    {
        var result = await new OpenLineSession(new RejectingOpener())
            .ExecuteAsync(ValidCommand(), CancellationToken.None);
        Assert.Equal(OpenLineSessionOutcome.Rejected, result.Outcome);
        Assert.Equal("LINE_NOT_AVAILABLE", result.ErrorCode);
        Assert.Equal("La línea no está libre para abrir una sesión.", result.ErrorMessage);
    }

    private static OpenLineSessionCommand ValidCommand() =>
        new(1, 2, 3, 4, false, Guid.NewGuid());

    private sealed class StubOpener(long sessionId) : ILineSessionOpener
    {
        public OpenLineSessionCommand? LastCommand { get; private set; }
        public Task<long> OpenAsync(
            OpenLineSessionCommand command, CancellationToken cancellationToken)
        {
            LastCommand = command;
            return Task.FromResult(sessionId);
        }
    }

    private sealed class RejectingOpener : ILineSessionOpener
    {
        public Task<long> OpenAsync(
            OpenLineSessionCommand command, CancellationToken cancellationToken) =>
            throw new LineSessionRejectedException(
                "LINE_NOT_AVAILABLE",
                "La línea no está libre para abrir una sesión.");
    }
}
