namespace Ebir.Mes.Application.LineSessions;

public interface ICurrentShiftTimeEntryCorrector
{
    Task CorrectAsync(
        CorrectCurrentShiftTimeEntryCommand command,
        CancellationToken cancellationToken);
}
