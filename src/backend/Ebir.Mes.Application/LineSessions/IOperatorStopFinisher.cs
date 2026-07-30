namespace Ebir.Mes.Application.LineSessions;

public interface IOperatorStopFinisher
{
    Task<FinishedOperatorStopRecord> FinishAsync(
        FinishOperatorStopCommand command, CancellationToken cancellationToken);
}
