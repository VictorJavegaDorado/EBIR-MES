namespace Ebir.Mes.Application.LineSessions;

public interface ILineSessionFinisher
{
    Task<int> FinishAsync(
        FinishLineSessionCommand command,
        CancellationToken cancellationToken);
}
