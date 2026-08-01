namespace Ebir.Mes.Application.Printing;

public sealed record PrintJobRecord(
    long PrintJobId,
    Guid PrintJobUid,
    long LabelId,
    Guid LabelUid,
    long RequestedPrinterId,
    string PrinterCode,
    string PrinterModel,
    string TemplateCode,
    int TemplateVersion,
    string LabelDataJson,
    short Copies,
    int AttemptNumber);
