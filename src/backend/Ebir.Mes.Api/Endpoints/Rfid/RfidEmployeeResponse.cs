namespace Ebir.Mes.Api.Endpoints.Rfid;

public sealed record RfidEmployeeResponse(
    long EmployeeId,
    string NavEmployeeCode,
    string FullName);
