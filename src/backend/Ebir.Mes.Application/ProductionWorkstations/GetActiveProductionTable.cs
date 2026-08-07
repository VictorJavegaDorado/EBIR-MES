namespace Ebir.Mes.Application.ProductionWorkstations;

public sealed class GetActiveProductionTable(IProductionTableStateReader reader)
{
    public Task<ActiveProductionTableRecord?> ExecuteAsync(
        long lineId,
        CancellationToken cancellationToken)
    {
        if (lineId <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(lineId));
        }

        return reader.ReadActiveByLineAsync(lineId, cancellationToken);
    }
}
