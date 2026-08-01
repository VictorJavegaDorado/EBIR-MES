namespace Ebir.Mes.Application.Printing;

public interface IPrinter
{
    Task<PrintReceipt> PrintAsync(
        PrintJobRecord job,
        CancellationToken cancellationToken);
}
