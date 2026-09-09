namespace Ebir.Mes.Application.Printing.LabelControl;

public interface ILabelControlReader
{
    Task<LabelControlSnapshotRecord> ReadAsync(CancellationToken cancellationToken);
}
