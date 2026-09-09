namespace Ebir.Mes.Application.Printing.LabelControl;

public sealed class GetLabelControl(ILabelControlReader reader)
{
    public Task<LabelControlSnapshotRecord> ExecuteAsync(
        CancellationToken cancellationToken) => reader.ReadAsync(cancellationToken);
}
