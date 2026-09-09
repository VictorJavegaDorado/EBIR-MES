namespace Ebir.Mes.Application.Rfid;

public sealed class AuthorizeSupervisorByRfid(
    IRfidCredentialFingerprinter fingerprinter,
    ISupervisorRfidReader reader)
{
    public async Task<SupervisorRfidAuthorizationResult> ExecuteAsync(
        string? rawCredential,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(rawCredential)) return Invalid();

        byte[] fingerprint;
        try
        {
            fingerprint = fingerprinter.Fingerprint(rawCredential);
        }
        catch (RfidCredentialInvalidException)
        {
            return Invalid();
        }

        var supervisor = await reader.ReadAsync(fingerprint, cancellationToken);
        return supervisor is null
            ? new(false, null, "RFID_SUPERVISOR_NOT_AUTHORIZED")
            : new(true, supervisor, null);
    }

    private static SupervisorRfidAuthorizationResult Invalid() =>
        new(false, null, "RFID_CREDENTIAL_INVALID");
}

public sealed record SupervisorRfidAuthorizationResult(
    bool Authorized,
    RfidEmployeeRecord? Supervisor,
    string? ErrorCode);
