namespace Ebir.Mes.Application.LineIdentification;

public sealed class IdentifyLine(ILineIdentificationReader reader)
{
    public const int MaximumCodeLength = 20;

    public async Task<LineIdentificationResult> ExecuteAsync(
        string? code,
        CancellationToken cancellationToken)
    {
        var normalizedCode = code?.Trim().ToUpperInvariant() ?? string.Empty;

        if (normalizedCode.Length == 0)
        {
            return Failure(
                LineIdentificationOutcome.InvalidCode,
                normalizedCode,
                "LINE_CODE_REQUIRED",
                "Introduce el código de la línea.");
        }

        if (normalizedCode.Length > MaximumCodeLength)
        {
            return Failure(
                LineIdentificationOutcome.InvalidCode,
                normalizedCode,
                "LINE_CODE_TOO_LONG",
                $"El código no puede superar {MaximumCodeLength} caracteres.");
        }

        var matches = await reader.FindByCodeAsync(normalizedCode, cancellationToken);

        if (matches.Count == 0)
        {
            return Failure(
                LineIdentificationOutcome.NotFound,
                normalizedCode,
                "LINE_NOT_FOUND",
                "No existe ninguna línea con ese código.");
        }

        if (matches.Count > 1)
        {
            return Failure(
                LineIdentificationOutcome.Ambiguous,
                normalizedCode,
                "LINE_CODE_AMBIGUOUS",
                "El código identifica líneas de más de un centro de trabajo.");
        }

        var line = matches[0];

        if (!line.IsActive)
        {
            return new LineIdentificationResult(
                LineIdentificationOutcome.Inactive,
                normalizedCode,
                line,
                "LINE_INACTIVE",
                "La línea está desactivada.");
        }

        return new LineIdentificationResult(
            LineIdentificationOutcome.Found,
            normalizedCode,
            line,
            null,
            null);
    }

    private static LineIdentificationResult Failure(
        LineIdentificationOutcome outcome,
        string normalizedCode,
        string errorCode,
        string errorMessage)
    {
        return new LineIdentificationResult(
            outcome,
            normalizedCode,
            null,
            errorCode,
            errorMessage);
    }
}

