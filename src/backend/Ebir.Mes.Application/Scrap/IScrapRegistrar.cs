namespace Ebir.Mes.Application.Scrap;

public interface IScrapRegistrar
{
    Task<RegisteredScrapRecord> RegisterAsync(
        RegisterScrapCommand command,
        CancellationToken cancellationToken);
}
