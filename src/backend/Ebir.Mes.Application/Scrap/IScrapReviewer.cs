namespace Ebir.Mes.Application.Scrap;

public interface IScrapReviewer
{
    Task<ReviewedScrapRecord> ReviewAsync(
        ReviewScrapCommand command,
        CancellationToken cancellationToken);
}
