namespace Ebir.Mes.Application.Replenishment;

public interface IReplenishmentRequestTransitioner
{
    Task TransitionAsync(
        TransitionReplenishmentRequestCommand command,
        CancellationToken cancellationToken);
}
