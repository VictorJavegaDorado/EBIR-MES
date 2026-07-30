namespace Ebir.Mes.Application.LineSessions;

public interface ILineSessionOpener
{
    Task<long> OpenAsync(
        OpenLineSessionCommand command,
        CancellationToken cancellationToken);
}
