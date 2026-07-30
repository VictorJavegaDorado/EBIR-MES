namespace Ebir.Mes.Application.LineIdentification;

public sealed record LineIdentificationRecord(
    long LineId,
    string Code,
    string Name,
    string WorkCenterCode,
    string WorkCenterName,
    bool IsActive,
    string OperationalStatus);

