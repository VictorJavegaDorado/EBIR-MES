namespace Ebir.Mes.Application.Pallets.ClosePalletOptions;

public sealed record PalletReservationOption(
    long Id,
    int ReservedQuantity,
    string OrderNumber,
    string ProductNumber,
    string ProductDescription,
    string ProductPostingGroup,
    string LineName);

public sealed record PalletEmployeeOption(
    long Id,
    string Code,
    string Name);

public sealed record PalletCloseOptionsRecord(
    IReadOnlyList<PalletReservationOption> Reservations,
    IReadOnlyList<PalletEmployeeOption> Employees,
    IReadOnlyList<PalletEmployeeOption> Supervisors);

public interface IPalletCloseOptionsReader
{
    Task<PalletCloseOptionsRecord> ReadAsync(
        long lineId,
        CancellationToken cancellationToken);
}

public sealed class PalletCloseOptionsUnavailableException(
    string message,
    Exception? innerException = null) : Exception(message, innerException);

public sealed class GetPalletCloseOptions(IPalletCloseOptionsReader reader)
{
    public Task<PalletCloseOptionsRecord> ExecuteAsync(
        long lineId,
        CancellationToken cancellationToken)
    {
        if (lineId <= 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(lineId),
                "lineId debe ser un identificador positivo.");
        }

        return reader.ReadAsync(lineId, cancellationToken);
    }
}
