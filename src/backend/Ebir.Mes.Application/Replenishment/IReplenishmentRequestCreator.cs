namespace Ebir.Mes.Application.Replenishment;

public interface IReplenishmentRequestCreator
{
    Task<long> CreateAsync(
        CreateReplenishmentRequestCommand command,
        CancellationToken cancellationToken);
}
