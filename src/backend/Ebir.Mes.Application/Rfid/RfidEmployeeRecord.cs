namespace Ebir.Mes.Application.Rfid;

public sealed record RfidEmployeeRecord(
    long EmployeeId,
    string NavEmployeeCode,
    string FullName);
