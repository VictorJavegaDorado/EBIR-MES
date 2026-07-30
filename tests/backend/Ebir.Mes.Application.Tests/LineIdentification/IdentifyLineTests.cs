using Ebir.Mes.Application.LineIdentification;
using Xunit;

namespace Ebir.Mes.Application.Tests.LineIdentification;

public sealed class IdentifyLineTests
{
    [Fact]
    public async Task ExecuteAsync_NormalizesCodeAndReturnsActiveLine()
    {
        var expectedLine = ActiveLine("L-01");
        var reader = new StubReader([expectedLine]);
        var useCase = new IdentifyLine(reader);

        var result = await useCase.ExecuteAsync("  l-01  ", CancellationToken.None);

        Assert.Equal(LineIdentificationOutcome.Found, result.Outcome);
        Assert.Equal("L-01", result.NormalizedCode);
        Assert.Same(expectedLine, result.Line);
        Assert.Equal("L-01", reader.LastCode);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsEmptyCodeWithoutCallingReader()
    {
        var reader = new StubReader([]);
        var useCase = new IdentifyLine(reader);

        var result = await useCase.ExecuteAsync("   ", CancellationToken.None);

        Assert.Equal(LineIdentificationOutcome.InvalidCode, result.Outcome);
        Assert.Equal("LINE_CODE_REQUIRED", result.ErrorCode);
        Assert.Equal(0, reader.CallCount);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsCodeLongerThanDatabaseField()
    {
        var reader = new StubReader([]);
        var useCase = new IdentifyLine(reader);

        var result = await useCase.ExecuteAsync(
            new string('X', IdentifyLine.MaximumCodeLength + 1),
            CancellationToken.None);

        Assert.Equal(LineIdentificationOutcome.InvalidCode, result.Outcome);
        Assert.Equal("LINE_CODE_TOO_LONG", result.ErrorCode);
        Assert.Equal(0, reader.CallCount);
    }

    [Fact]
    public async Task ExecuteAsync_ReturnsNotFoundWhenReaderHasNoMatches()
    {
        var useCase = new IdentifyLine(new StubReader([]));

        var result = await useCase.ExecuteAsync("L-99", CancellationToken.None);

        Assert.Equal(LineIdentificationOutcome.NotFound, result.Outcome);
        Assert.Equal("LINE_NOT_FOUND", result.ErrorCode);
    }

    [Fact]
    public async Task ExecuteAsync_ReturnsInactiveLineWithoutAllowingContinuation()
    {
        var inactiveLine = ActiveLine("L-01") with { IsActive = false };
        var useCase = new IdentifyLine(new StubReader([inactiveLine]));

        var result = await useCase.ExecuteAsync("L-01", CancellationToken.None);

        Assert.Equal(LineIdentificationOutcome.Inactive, result.Outcome);
        Assert.Equal("LINE_INACTIVE", result.ErrorCode);
        Assert.Same(inactiveLine, result.Line);
    }

    [Fact]
    public async Task ExecuteAsync_DoesNotChooseArbitrarilyWhenCodeIsAmbiguous()
    {
        var useCase = new IdentifyLine(new StubReader([
            ActiveLine("L-01"),
            ActiveLine("L-01") with { LineId = 2, WorkCenterCode = "CT-02" }
        ]));

        var result = await useCase.ExecuteAsync("L-01", CancellationToken.None);

        Assert.Equal(LineIdentificationOutcome.Ambiguous, result.Outcome);
        Assert.Equal("LINE_CODE_AMBIGUOUS", result.ErrorCode);
        Assert.Null(result.Line);
    }

    private static LineIdentificationRecord ActiveLine(string code)
    {
        return new LineIdentificationRecord(
            1,
            code,
            "Línea de prueba",
            "CT-01",
            "Centro de prueba",
            true,
            "LIBRE");
    }

    private sealed class StubReader(IReadOnlyList<LineIdentificationRecord> matches)
        : ILineIdentificationReader
    {
        public int CallCount { get; private set; }

        public string? LastCode { get; private set; }

        public Task<IReadOnlyList<LineIdentificationRecord>> FindByCodeAsync(
            string normalizedCode,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CallCount++;
            LastCode = normalizedCode;
            return Task.FromResult(matches);
        }
    }
}
