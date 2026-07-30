namespace Ebir.Mes.Application.LineSessions;

public interface IProductiveEntryRegistrar
{
    Task<ProductiveEntryRecord> RegisterAsync(
        RegisterProductiveEntryCommand command,
        CancellationToken cancellationToken);
}
