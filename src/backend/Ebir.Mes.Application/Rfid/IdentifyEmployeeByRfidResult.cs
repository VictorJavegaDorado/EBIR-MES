namespace Ebir.Mes.Application.Rfid;

public sealed record IdentifyEmployeeByRfidResult(
    IdentifyEmployeeByRfidOutcome Outcome,
    RfidEmployeeRecord? Employee,
    string? ErrorCode);
