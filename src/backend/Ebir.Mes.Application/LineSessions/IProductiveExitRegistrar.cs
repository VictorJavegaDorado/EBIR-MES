namespace Ebir.Mes.Application.LineSessions;

public interface IProductiveExitRegistrar
{
    Task<int> RegisterAsync(
        RegisterProductiveExitCommand command,
        CancellationToken cancellationToken);
}
