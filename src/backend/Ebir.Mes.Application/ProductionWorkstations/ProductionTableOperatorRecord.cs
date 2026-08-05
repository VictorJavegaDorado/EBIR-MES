namespace Ebir.Mes.Application.ProductionWorkstations;

public sealed record ProductionTableOperatorRecord(
    long EmployeeId,
    string NavEmployeeCode,
    string FullName,
    DateTime EntryAtUtc,
    long ProductiveSeconds,
    string Status);
