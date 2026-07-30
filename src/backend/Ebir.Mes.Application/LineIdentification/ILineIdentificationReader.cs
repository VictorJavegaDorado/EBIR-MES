namespace Ebir.Mes.Application.LineIdentification;

public interface ILineIdentificationReader
{
    Task<IReadOnlyList<LineIdentificationRecord>> FindByCodeAsync(
        string normalizedCode,
        CancellationToken cancellationToken);
}

