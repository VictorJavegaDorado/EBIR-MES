namespace Ebir.Mes.Application.Rfid;

public sealed class IdentifyEmployeeByRfid(
    IRfidCredentialFingerprinter fingerprinter,
    IRfidEmployeeReader reader)
{
    public async Task<IdentifyEmployeeByRfidResult> ExecuteAsync(
        string? rawCredential,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(rawCredential))
            return Invalid();
        byte[] fingerprint;
        try
        {
            fingerprint = fingerprinter.Fingerprint(rawCredential);
        }
        catch (RfidCredentialInvalidException)
        {
            return Invalid();
        }

        var employee = await reader.ReadAsync(fingerprint, cancellationToken);
        return employee is null
            ? new(IdentifyEmployeeByRfidOutcome.NotFound, null, "RFID_CREDENTIAL_NOT_FOUND")
            : new(IdentifyEmployeeByRfidOutcome.Identified, employee, null);
    }

    private static IdentifyEmployeeByRfidResult Invalid() =>
        new(IdentifyEmployeeByRfidOutcome.InvalidCredential, null, "RFID_CREDENTIAL_INVALID");
}
