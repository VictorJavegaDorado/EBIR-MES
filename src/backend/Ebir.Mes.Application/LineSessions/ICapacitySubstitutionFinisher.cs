namespace Ebir.Mes.Application.LineSessions;

public interface ICapacitySubstitutionFinisher
{
    Task<int> FinishAsync(
        FinishCapacitySubstitutionCommand command,
        CancellationToken cancellationToken);
}
