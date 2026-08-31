namespace Ebir.Mes.Application.Printing;

public interface IPalletLabelReprinter
{
    Task<ReprintedPalletLabelRecord> ReprintAsync(
        ReprintPalletLabelCommand command,
        CancellationToken cancellationToken);
}
