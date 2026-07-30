namespace Ebir.Mes.Application.LineSessions;

public interface IOperatorStopStarter
{
    Task<OperatorStopRecord> StartAsync(
        StartOperatorStopCommand command, CancellationToken cancellationToken);
}
