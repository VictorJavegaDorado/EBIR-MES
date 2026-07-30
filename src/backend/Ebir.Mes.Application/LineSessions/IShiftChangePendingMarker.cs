namespace Ebir.Mes.Application.LineSessions;

public interface IShiftChangePendingMarker
{
    Task<bool> MarkAsync(
        MarkShiftChangePendingCommand command,
        CancellationToken cancellationToken);
}
