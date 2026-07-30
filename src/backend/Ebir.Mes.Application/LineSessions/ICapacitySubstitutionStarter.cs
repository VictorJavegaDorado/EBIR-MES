namespace Ebir.Mes.Application.LineSessions;

public interface ICapacitySubstitutionStarter
{
    Task<CapacitySubstitutionRecord> StartAsync(
        StartCapacitySubstitutionCommand command,
        CancellationToken cancellationToken);
}
