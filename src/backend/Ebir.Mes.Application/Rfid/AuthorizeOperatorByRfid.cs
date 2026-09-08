namespace Ebir.Mes.Application.Rfid;

public sealed class AuthorizeOperatorByRfid(IdentifyEmployeeByRfid identifyEmployee)
{
    public async Task<AuthorizeOperatorByRfidResult> ExecuteAsync(
        long targetEmployeeId,
        string? rawCredential,
        CancellationToken cancellationToken)
    {
        if (targetEmployeeId <= 0)
        {
            return new(false, "EMPLOYEE_ID_INVALID",
                "El operario seleccionado no es válido.");
        }

        var identification = await identifyEmployee.ExecuteAsync(
            rawCredential,
            cancellationToken);
        if (identification.Outcome != IdentifyEmployeeByRfidOutcome.Identified)
        {
            return new(false, identification.ErrorCode ?? "RFID_CREDENTIAL_INVALID",
                "La tarjeta RFID no está autorizada para esta acción.");
        }

        if (identification.Employee!.EmployeeId != targetEmployeeId)
        {
            return new(false, "RFID_OPERATOR_MISMATCH",
                "La tarjeta RFID no pertenece al operario seleccionado.");
        }

        return new(true, null, null);
    }
}

public sealed record AuthorizeOperatorByRfidResult(
    bool Authorized,
    string? ErrorCode,
    string? ErrorMessage);
