namespace Ebir.Mes.Api.Endpoints.LineIdentification;

public sealed record LineIdentificationResponse(
    long Id,
    string Code,
    string Name,
    string WorkCenterCode,
    string WorkCenterName,
    string OperationalStatus);

